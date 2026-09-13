import Foundation

extension OpenAIResponsesPublicSanitizer {
    static func functionCall(_ item: [String: Any]) throws -> [String: Any] {
        let custom = item["type"] as? String == "custom_tool_call"
        let inputKey = custom ? "input" : "arguments"
        guard let id = nonemptyResponsesString(item["id"]),
            let callID = nonemptyResponsesString(item["call_id"]),
            let name = nonemptyResponsesString(item["name"]),
            let arguments = item[inputKey] as? String
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var result: [String: Any] = [
            "id": id,
            "type": custom ? "custom_tool_call" : "function_call",
            "call_id": callID,
            "name": name,
            inputKey: arguments,
        ]
        // vLLM echoes namespace as an explicit null on function_call
        // items: null means absent; a non-string value stays malformed.
        if let namespace = item["namespace"], !(namespace is NSNull) {
            guard let namespace = namespace as? String else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            result["namespace"] = namespace
        }
        try copyStatus(from: item, to: &result)
        try copyInternalMetadata(from: item, to: &result)
        if !custom {
            result[ResponsesAgentMail.Field.encryptedFunctionArguments.rawValue] =
                try ResponsesAgentMail.encryptedArguments(item)
        }
        return result
    }
}
