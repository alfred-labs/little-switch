import Foundation

package struct ResponsesFunctionMetadata {
    let callID: String
    let name: String
    /// The namespace a backend that natively restores the pair emits with the
    /// call; nil on plain flattened providers.
    let namespace: String?

    init(callID: String, name: String, namespace: String? = nil) {
        self.callID = callID
        self.name = name
        self.namespace = namespace
    }
}

package func responsesFunctionMetadata(
    _ item: [String: Any],
    required: Bool
) throws -> ResponsesFunctionMetadata? {
    guard required else {
        return nil
    }
    guard let callID = nonemptyResponsesString(item["call_id"]),
        let name = nonemptyResponsesString(item["name"]),
        item["arguments"] is String
    else {
        throw OpenAIResponsesWebSearch.Error.invalidResponse
    }
    return ResponsesFunctionMetadata(
        callID: callID,
        name: name,
        namespace: try responsesFunctionNamespace(item["namespace"])
    )
}

/// An explicit null or an absent field means "no namespace"; any other
/// non-string value is a malformed frame.
private func responsesFunctionNamespace(_ value: Any?) throws -> String? {
    guard let value, !(value is NSNull) else {
        return nil
    }
    guard let namespace = value as? String, !namespace.isEmpty else {
        throw OpenAIResponsesWebSearch.Error.invalidResponse
    }
    return namespace
}
