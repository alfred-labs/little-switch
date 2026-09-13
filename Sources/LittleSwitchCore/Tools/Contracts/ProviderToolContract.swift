import Foundation
import LittleSwitchTransport

package struct ProviderToolContract: Sendable {
    package enum Wire: Equatable, Sendable {
        case anthropic
        case responses
        case chatCompletions
    }

    package enum Error: Swift.Error, Equatable, Sendable {
        case invalidRequest
        case invalidResponse
        case undeclaredTool(name: String, namespace: String? = nil)
        case providerOwnedTool
    }

    private let wire: Wire
    private let catalog: ProviderToolContractCatalog
    private let resolver: ProviderToolNamespaceResolver?
    private var chat = ProviderToolContractChatStream()
    private var responseCalls: [String: ProviderToolContractCatalog.Identity] = [:]

    package init(
        wire: Wire,
        requestBody: Data,
        declaredToolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
        toolNameCatalog: ProviderToolNameCatalog? = nil
    ) throws {
        self.wire = wire
        catalog = try ProviderToolContractCatalog(wire: wire, requestBody: requestBody)
        let requestNames = catalog.nameCatalog
        let reservedNames = ProviderToolNameCatalog(
            declared: requestNames.declared.union(toolNameCatalog?.declared ?? []),
            historical: requestNames.historical.union(toolNameCatalog?.historical ?? [])
        )
        resolver =
            declaredToolBindings.isEmpty
            ? nil
            : ProviderToolNamespaceResolver(
                declaredBindings: declaredToolBindings,
                nameCatalog: reservedNames
            )
    }

    package func validateBuffered(_ body: Data) throws {
        let root = try providerToolObject(body, failure: .invalidResponse)
        switch wire {
        case .anthropic:
            try validateBlocks(root["content"])
        case .responses:
            try validateBlocks(root["output"])
        case .chatCompletions:
            for choice in try providerToolObjects(root["choices"]) {
                if let message = choice["message"] {
                    guard let message = message as? [String: Any] else { throw Error.invalidResponse }
                    try validateChatMessage(message)
                }
            }
        }
    }

    package mutating func validateFrame(_ frame: ServerSentEventFrame) throws {
        if frame.terminal {
            try finish()
            return
        }
        guard !frame.data.isEmpty else { return }
        let root = try providerToolObject(frame.data, failure: .invalidResponse)
        switch wire {
        case .anthropic:
            if let block = root["content_block"] {
                guard let block = block as? [String: Any] else { throw Error.invalidResponse }
                try validateBlock(block)
            }
            if let message = root["message"] {
                guard let message = message as? [String: Any] else { throw Error.invalidResponse }
                try validateBlocks(message["content"])
            }
            if let delta = root["delta"] as? [String: Any] { try validateBlock(delta) }
        case .responses:
            for type in [frame.event, root["type"] as? String].compactMap(\.self) {
                try validateResponseEventType(type)
            }
            try validateResponseFrame(root, event: frame.event)
        case .chatCompletions:
            try chat.consume(root, catalog: catalog, resolver: resolver)
        }
    }

    /// Call before publishing a successful terminal and at stream EOF. A viable
    /// streaming name prefix is not permission to publish an incomplete call.
    package func finish() throws {
        try chat.finish(catalog: catalog, resolver: resolver)
    }

    private func validateBlocks(_ value: Any?) throws {
        for block in try providerToolObjects(value) {
            try validateBlock(block)
        }
    }

    private func validateBlock(_ block: [String: Any]) throws {
        let type = block["type"] as? String ?? ""
        switch (wire, type) {
        case (.anthropic, "tool_use"), (.responses, "function_call"):
            _ = try validatedIdentity(name: block["name"], namespace: block["namespace"], kind: .function)
        case (.responses, "custom_tool_call"):
            _ = try validatedIdentity(name: block["name"], namespace: block["namespace"], kind: .custom)
        case (.responses, "message"):
            try validateBlocks(block["content"])
        default:
            if providerOwnedToolType(type) { throw Error.providerOwnedTool }
        }
    }

    private func validateChatMessage(_ message: [String: Any]) throws {
        try validateProviderToolFreeContent(message["content"])
        for call in try providerToolObjects(message["tool_calls"]) {
            guard let type = call["type"] as? String else { throw Error.invalidResponse }
            guard let kind = ProviderToolContractCatalog.Kind(rawValue: type) else {
                throw Error.providerOwnedTool
            }
            guard let function = call[type] as? [String: Any] else { throw Error.invalidResponse }
            _ = try validatedIdentity(name: function["name"], namespace: function["namespace"], kind: kind)
        }
        if let function = message["function_call"] {
            guard let function = function as? [String: Any] else { throw Error.invalidResponse }
            _ = try validatedIdentity(name: function["name"], namespace: function["namespace"], kind: .function)
        }
    }

    /// The declared identity an emitted call denotes: the exact catalog
    /// identity first, then — only for names the request itself declared as
    /// namespace children — the wire name a near-miss resolves to.
    private func validatedIdentity(
        name: Any?,
        namespace: Any? = nil,
        kind: ProviderToolContractCatalog.Kind
    ) throws -> ProviderToolContractCatalog.Identity {
        do {
            return try catalog.validate(name: name, namespace: namespace, kind: kind)
        } catch let original as ProviderToolContract.Error {
            guard case .undeclaredTool = original else { throw original }
            guard let resolver,
                let emitted = name as? String, !emitted.isEmpty,
                let wireName = resolver.wireName(for: emitted, namespace: Self.suppliedNamespace(namespace))
            else {
                throw original
            }
            // The resolver only returns names built from the request's own
            // declarations; re-validating keeps that invariant local.
            do {
                return try catalog.validate(name: wireName, kind: kind)
            } catch ProviderToolContract.Error.undeclaredTool {
                throw original
            }
        }
    }

    private static func suppliedNamespace(_ value: Any?) -> String? {
        guard let value, !(value is NSNull), let namespace = value as? String, !namespace.isEmpty else {
            return nil
        }
        return namespace
    }

    private mutating func validateResponseFrame(_ root: [String: Any], event: String?) throws {
        if let part = root["part"] {
            guard let part = part as? [String: Any] else { throw Error.invalidResponse }
            try validateBlock(part)
        }
        if let item = root["item"] {
            guard let item = item as? [String: Any] else { throw Error.invalidResponse }
            try validateResponseItem(item)
        }
        if let response = root["response"] {
            guard let response = response as? [String: Any] else { throw Error.invalidResponse }
            for item in try providerToolObjects(response["output"]) {
                try validateResponseItem(item)
            }
        }
        let type = root["type"] as? String ?? event ?? ""
        let function = type.hasPrefix("response.function_call_arguments.")
        let custom = type.hasPrefix("response.custom_tool_call_input.")
        if function || custom {
            guard let id = root["item_id"] as? String, let identity = responseCalls[id],
                identity.kind == (function ? .function : .custom)
            else { throw Error.invalidResponse }
            // Some providers repeat unchanged metadata as explicit nulls.
            let name = root["name"] is NSNull ? nil : root["name"]
            let namespace = root["namespace"] is NSNull ? nil : root["namespace"]
            let supplied = try validatedIdentity(
                name: name ?? identity.name, namespace: namespace ?? identity.namespace, kind: identity.kind)
            guard supplied == identity else { throw Error.invalidResponse }
        }
    }

    private mutating func validateResponseItem(_ item: [String: Any]) throws {
        try validateBlock(item)
        let type = item["type"] as? String
        if type == "function_call" || type == "custom_tool_call" {
            guard let id = item["id"] as? String, !id.isEmpty else { throw Error.invalidResponse }
            let identity = try validatedIdentity(
                name: item["name"], namespace: item["namespace"], kind: type == "function_call" ? .function : .custom
            )
            guard responseCalls[id] == nil || responseCalls[id] == identity else { throw Error.invalidResponse }
            responseCalls[id] = identity
        }
    }

    private func validateResponseEventType(_ type: String) throws {
        guard type.hasPrefix("response.") else { return }
        let component = type.dropFirst("response.".count).split(separator: ".").first.map(String.init) ?? ""
        guard component != "function_call_arguments", component != "custom_tool_call_input" else { return }
        if providerOwnedToolType(component) { throw Error.providerOwnedTool }
    }
}

func providerToolObject(_ data: Data, failure: ProviderToolContract.Error) throws -> [String: Any] {
    guard let object = try? WireJSONCompatibility.fields(data) else { throw failure }
    return object
}

func providerToolObjects(
    _ value: Any?,
    failure: ProviderToolContract.Error = .invalidResponse
) throws -> [[String: Any]] {
    guard let value, !(value is NSNull) else { return [] }
    guard let objects = value as? [[String: Any]] else { throw failure }
    return objects
}

private func providerOwnedToolType(_ type: String) -> Bool {
    type == "tool_use" || type == "tool_result" || type == "tool_search_output"
        || type == "web_search" || type == "file_search" || type == "code_execution"
        || type.hasSuffix("_call") || type.hasSuffix("_call_output")
        || type.hasSuffix("_tool_use") || type.hasSuffix("_tool_result")
        || type.hasPrefix("mcp_") || type.contains("_call_")
}

func validateProviderToolFreeContent(_ content: Any?) throws {
    guard content is [Any] else { return }
    for block in try providerToolObjects(content) where providerOwnedToolType(block["type"] as? String ?? "") {
        throw ProviderToolContract.Error.providerOwnedTool
    }
}
