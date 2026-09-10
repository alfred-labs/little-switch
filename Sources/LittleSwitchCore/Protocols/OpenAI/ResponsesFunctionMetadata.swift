package struct ResponsesFunctionMetadata {
    let callID: String
    let name: String
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
    return ResponsesFunctionMetadata(callID: callID, name: name)
}
