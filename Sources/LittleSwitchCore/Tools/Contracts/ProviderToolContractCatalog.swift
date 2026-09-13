import Foundation
import LittleSwitchWire

/// Request-local identities only. Historical calls never grant permission to emit a new call.
struct ProviderToolContractCatalog: Sendable {
    typealias Kind = OpenAIChatToolKind

    struct Identity: Hashable, Sendable {
        let name: String
        let namespace: String?
        let kind: Kind
    }

    private var identities: Set<Identity> = []
    private(set) var allowedIdentities: Set<Identity> = []
    private var historicalNames: Set<String> = []

    private init() {}

    static func validateResponsesDeclarations(_ tools: [[String: Any]]) throws {
        var catalog = Self()
        for tool in tools { try catalog.insertResponses(tool) }
    }

    var nameCatalog: ProviderToolNameCatalog {
        ProviderToolNameCatalog(
            declared: Set(identities.filter { $0.namespace == nil }.map(\.name)),
            historical: historicalNames
        )
    }

    init(wire: ProviderToolContract.Wire, requestBody: Data) throws {
        let root = try providerToolObject(requestBody, failure: .invalidRequest)
        historicalNames = ProviderToolNameCatalog.history(in: root, wire: wire)
        for tool in try providerToolObjects(root["tools"], failure: .invalidRequest) {
            switch wire {
            case .anthropic:
                let type = tool["type"] as? String ?? "custom"
                let hosted = [
                    "web_search", "web_fetch", "code_execution", "tool_search_tool_regex", "tool_search_tool_bm25",
                ].contains {
                    type == $0 || type.hasPrefix("\($0)_")
                }
                if !hosted { try insert(tool, kind: .function) }
            case .responses:
                try insertResponses(tool)
            case .chatCompletions:
                if let type = tool["type"] as? String, let kind = Kind(rawValue: type) {
                    guard let function = tool[type] as? [String: Any] else {
                        throw ProviderToolContract.Error.invalidRequest
                    }
                    try insert(function, kind: kind)
                }
            }
        }
        if wire == .chatCompletions {
            for function in try providerToolObjects(root["functions"], failure: .invalidRequest) {
                try insert(function, kind: .function)
            }
        }
        allowedIdentities =
            try ProviderToolAllowedSelection.identities(in: root, wire: wire, declared: identities) ?? identities
    }

    @discardableResult
    func validate(name: Any?, namespace: Any? = nil, kind: Kind) throws -> Identity {
        guard let name = name as? String, !name.isEmpty else { throw ProviderToolContract.Error.invalidResponse }
        let namespace = try namespaceString(namespace, failure: .invalidResponse)
        let identity = Identity(name: name, namespace: namespace, kind: kind)
        guard allowedIdentities.contains(identity) else {
            throw ProviderToolContract.Error.undeclaredTool(name: name, namespace: namespace)
        }
        return identity
    }

    func validatePrefix(_ prefix: String, kind: Kind) throws {
        guard allowedIdentities.contains(where: { $0.kind == kind && $0.namespace == nil && $0.name.hasPrefix(prefix) })
        else {
            throw ProviderToolContract.Error.undeclaredTool(name: prefix)
        }
    }

    private mutating func insert(_ tool: [String: Any], namespace: String? = nil, kind: Kind) throws {
        guard let name = tool["name"] as? String, !name.isEmpty else {
            throw ProviderToolContract.Error.invalidRequest
        }
        // One public namespace/name pair must select one declaration. The
        // namespace inverse deliberately does not guess between tool kinds.
        guard !identities.contains(where: { $0.name == name && $0.namespace == namespace }) else {
            throw ProviderToolContract.Error.invalidRequest
        }
        identities.insert(Identity(name: name, namespace: namespace, kind: kind))
    }

    private mutating func insertResponses(_ tool: [String: Any]) throws {
        if tool["type"] as? String == "namespace" {
            guard let name = tool["name"] as? String, !name.isEmpty,
                let children = tool["tools"] as? [[String: Any]]
            else { throw ProviderToolContract.Error.invalidRequest }
            for child in children {
                if let type = child["type"] as? String, let kind = Kind(rawValue: type) {
                    try insert(child, namespace: name, kind: kind)
                }
            }
        } else if let type = tool["type"] as? String, let kind = Kind(rawValue: type) {
            try insert(tool, kind: kind)
        }
    }

    private func namespaceString(_ value: Any?, failure: ProviderToolContract.Error) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let namespace = value as? String, !namespace.isEmpty else { throw failure }
        return namespace
    }
}
