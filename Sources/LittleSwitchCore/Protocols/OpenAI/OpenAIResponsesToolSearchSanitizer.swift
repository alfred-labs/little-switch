import Foundation

extension OpenAIResponsesPublicSanitizer {
    static func clientToolSearchCall(_ item: [String: Any]) throws -> [String: Any] {
        guard let id = nonemptyResponsesString(item["id"]),
            item["execution"] as? String == "client",
            let callID = nonemptyResponsesString(item["call_id"]),
            let arguments = item["arguments"] as? [String: Any]
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var result: [String: Any] = [
            "id": id, "type": "tool_search_call", "execution": "client",
            "call_id": callID, "arguments": arguments,
        ]
        try copyStatus(from: item, to: &result)
        return result
    }
}
