import Foundation

/// Only identity fragments are retained. Arguments remain opaque and are not copied.
struct ProviderToolContractChatStream: Sendable {
    private struct Key: Hashable, Sendable {
        let choice: Int
        let tool: Int

        func hash(into hasher: inout Hasher) {
            hasher.combine(choice)
            hasher.combine(tool)
        }
    }

    private struct Call: Sendable {
        let kind: ProviderToolContractCatalog.Kind
        var name = ""
        var namespace: String?
    }

    private var calls: [Key: Call] = [:]
    private var finishedChoices: Set<Int> = []

    /// With declared namespace bindings the accumulated name may be a
    /// fragment of a near-miss (`functions.collaboration.` …), so per-fragment
    /// prefix validation cannot run; identity is instead settled when each
    /// call's name completes and at stream end. Without bindings the
    /// fail-closed per-fragment prefix check applies as before.
    mutating func consume(
        _ root: [String: Any],
        catalog: ProviderToolContractCatalog,
        resolver: ProviderToolNamespaceResolver?
    ) throws {
        for choice in try providerToolObjects(root["choices"]) {
            let delta = choice["delta"] as? [String: Any] ?? [:]
            try validateProviderToolFreeContent(delta["content"])
            let toolCalls = try providerToolObjects(delta["tool_calls"])
            if !toolCalls.isEmpty || delta["function_call"] != nil {
                let index = try validIndex(choice["index"])
                guard !finishedChoices.contains(index) else { throw ProviderToolContract.Error.invalidResponse }
                for call in toolCalls {
                    let key = Key(choice: index, tool: try validIndex(call["index"]))
                    try consumeCall(call, key: key, catalog: catalog, resolver: resolver)
                }
                if let function = delta["function_call"] {
                    try consumeCall(
                        ["type": "function", "function": function],
                        key: Key(choice: index, tool: -1),
                        catalog: catalog,
                        resolver: resolver
                    )
                }
            }
            if let reason = choice["finish_reason"], !(reason is NSNull) {
                let index = try validIndex(choice["index"])
                try finish(choice: index, catalog: catalog, resolver: resolver)
                finishedChoices.insert(index)
            }
        }
    }

    func finish(catalog: ProviderToolContractCatalog, resolver: ProviderToolNamespaceResolver?) throws {
        for call in calls.values {
            try validateCompletedName(call, catalog: catalog, resolver: resolver)
        }
    }

    private func finish(
        choice: Int,
        catalog: ProviderToolContractCatalog,
        resolver: ProviderToolNamespaceResolver?
    ) throws {
        for (key, call) in calls where key.choice == choice {
            try validateCompletedName(call, catalog: catalog, resolver: resolver)
        }
    }

    private func validateCompletedName(
        _ call: Call,
        catalog: ProviderToolContractCatalog,
        resolver: ProviderToolNamespaceResolver?
    ) throws {
        do {
            try catalog.validate(name: call.name, namespace: call.namespace, kind: call.kind)
        } catch ProviderToolContract.Error.undeclaredTool {
            guard let resolver,
                !call.name.isEmpty,
                let wireName = resolver.wireName(for: call.name, namespace: call.namespace)
            else {
                throw ProviderToolContract.Error.undeclaredTool
            }
            try catalog.validate(name: wireName, kind: call.kind)
        }
    }

    private mutating func consumeCall(
        _ delta: [String: Any],
        key: Key,
        catalog: ProviderToolContractCatalog,
        resolver: ProviderToolNamespaceResolver?
    ) throws {
        let previous = calls[key]
        let rawKind = delta["type"] as? String ?? previous?.kind.rawValue ?? "function"
        guard let kind = ProviderToolContractCatalog.Kind(rawValue: rawKind) else {
            throw ProviderToolContract.Error.providerOwnedTool
        }
        guard previous == nil || previous?.kind == kind else { throw ProviderToolContract.Error.invalidResponse }
        var call = previous ?? Call(kind: kind)
        if let function = delta[rawKind] {
            guard let function = function as? [String: Any] else { throw ProviderToolContract.Error.invalidResponse }
            if let value = function["namespace"], !(value is NSNull) {
                guard let namespace = value as? String, !namespace.isEmpty,
                    call.namespace == nil || call.namespace == namespace
                else { throw ProviderToolContract.Error.invalidResponse }
                call.namespace = namespace
            }
            if let name = function["name"], !(name is NSNull) {
                guard let name = name as? String else { throw ProviderToolContract.Error.invalidResponse }
                let repeatedIdentity =
                    name == call.name && (try? validateCompletedName(call, catalog: catalog, resolver: resolver)) != nil
                if !repeatedIdentity { call.name += name }
            }
        }
        if resolver == nil, call.namespace == nil {
            try catalog.validatePrefix(call.name, kind: kind)
        }
        calls[key] = call
    }

    private func validIndex(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            let index = value as? Int, index >= 0
        else { throw ProviderToolContract.Error.invalidResponse }
        return index
    }
}
