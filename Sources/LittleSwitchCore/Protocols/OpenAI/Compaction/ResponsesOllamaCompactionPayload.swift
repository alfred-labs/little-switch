import Foundation

struct ResponsesOllamaStandaloneName: Sendable {
    let name: String
    let namespace: String
}

/// Reads the versioned legacy format without guessing identities from dotted wire names.
enum ResponsesOllamaCompactionPayload {
    static func expand(_ payload: [String: Any]) throws -> [[String: Any]] {
        guard Set(payload.keys).isSubset(of: ["type", "version", "summary", "retained", "standalone_names"]),
            nonnegativeResponsesIndex(payload["version"]) == 1,
            let summary = ResponsesCompactionJSON.nonempty(payload["summary"])
        else { throw ResponsesCompactionError.invalidPayload }
        let records: [[String: Any]] = try ResponsesOllamaCompactionMessage.array(payload["retained"])
        let messages = try records.map(ResponsesOllamaCompactionMessage.init)
        let names = try standaloneNames(payload["standalone_names"], messages: messages)
        var result = [ResponsesCompactionPayload.summaryMessage(summary)]
        for (index, message) in messages.enumerated() {
            result += try message.responsesItems(standalone: names[index])
        }
        return result
    }

    private static func standaloneNames(
        _ value: Any?, messages: [ResponsesOllamaCompactionMessage]
    ) throws -> [Int: ResponsesOllamaStandaloneName] {
        guard let value, !(value is NSNull) else { return [:] }
        guard let entries = value as? [String: Any] else { throw ResponsesCompactionError.invalidPayload }
        var result: [Int: ResponsesOllamaStandaloneName] = [:]
        for (key, value) in entries {
            guard let index = Int(key), String(index) == key, messages.indices.contains(index),
                let pair = value as? [String: Any], Set(pair.keys).isSubset(of: ["name", "namespace"]),
                let name = pair["name"] as? String, ResponsesCompactionJSON.nonempty(name) != nil
            else { throw ResponsesCompactionError.invalidPayload }
            let namespace = try ResponsesOllamaCompactionMessage.string(pair["namespace"])
            let message = messages[index]
            guard message.role == "tool", message.toolCallID.isEmpty,
                message.toolName == legacyWireName(namespace: namespace, name: name)
            else { throw ResponsesCompactionError.invalidPayload }
            result[index] = ResponsesOllamaStandaloneName(name: name, namespace: namespace)
        }
        return result
    }

    /// This spelling is only a legacy consistency check; the explicit pair is the identity.
    private static func legacyWireName(namespace: String, name: String) -> String {
        if namespace.isEmpty || name.hasPrefix(namespace + ".") || name.hasPrefix(namespace + "_") { return name }
        return namespace + (name.hasPrefix("_") ? "" : ".") + name
    }
}
