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
    }

    private var calls: [Key: Call] = [:]
    private var finishedChoices: Set<Int> = []

    mutating func consume(_ root: [String: Any], catalog: ProviderToolContractCatalog) throws {
        for choice in try providerToolObjects(root["choices"]) {
            let delta = choice["delta"] as? [String: Any] ?? [:]
            try validateProviderToolFreeContent(delta["content"])
            let toolCalls = try providerToolObjects(delta["tool_calls"])
            if !toolCalls.isEmpty || delta["function_call"] != nil {
                let index = try validIndex(choice["index"])
                guard !finishedChoices.contains(index) else { throw ProviderToolContract.Error.invalidResponse }
                for call in toolCalls {
                    let key = Key(choice: index, tool: try validIndex(call["index"]))
                    try consumeCall(call, key: key, catalog: catalog)
                }
                if let function = delta["function_call"] {
                    try consumeCall(
                        ["type": "function", "function": function], key: Key(choice: index, tool: -1), catalog: catalog)
                }
            }
            if let reason = choice["finish_reason"], !(reason is NSNull) {
                let index = try validIndex(choice["index"])
                try finish(choice: index, catalog: catalog)
                finishedChoices.insert(index)
            }
        }
    }

    func finish(catalog: ProviderToolContractCatalog) throws {
        for call in calls.values {
            try catalog.validate(name: call.name, kind: call.kind)
        }
    }

    private func finish(choice: Int, catalog: ProviderToolContractCatalog) throws {
        for (key, call) in calls where key.choice == choice {
            try catalog.validate(name: call.name, kind: call.kind)
        }
    }

    private mutating func consumeCall(
        _ delta: [String: Any],
        key: Key,
        catalog: ProviderToolContractCatalog
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
            if let name = function["name"], !(name is NSNull) {
                guard let name = name as? String else { throw ProviderToolContract.Error.invalidResponse }
                let repeatedIdentity = name == call.name && (try? catalog.validate(name: name, kind: kind)) != nil
                if !repeatedIdentity { call.name += name }
            }
        }
        try catalog.validatePrefix(call.name, kind: kind)
        calls[key] = call
    }

    private func validIndex(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            let index = value as? Int, index >= 0
        else { throw ProviderToolContract.Error.invalidResponse }
        return index
    }
}
