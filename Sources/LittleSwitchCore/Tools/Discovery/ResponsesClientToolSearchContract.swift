import Foundation

/// Identity of the ordinary function used to transport client-owned discovery.
/// The name is reserved against this request's declarations and replayed calls.
package struct ResponsesClientToolSearchContract: Equatable, Sendable {
    package let wireName: String

    package func owns(_ item: [String: Any]) -> Bool {
        item["type"] as? String == "function_call"
            && item["name"] as? String == wireName
            && nonemptyResponsesString(item["namespace"]) == nil
    }

    package func projectItem(_ item: [String: Any], starting: Bool = false) throws -> [String: Any] {
        guard owns(item) else { return item }
        guard let id = nonemptyResponsesString(item["id"]),
            let callID = nonemptyResponsesString(item["call_id"])
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let arguments: [String: Any]
        if starting {
            arguments = [:]
        } else {
            guard let string = item["arguments"] as? String,
                let object = try? WireJSONCompatibility.fields(Data(string.utf8))
            else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            arguments = object
        }
        return [
            "id": id,
            "type": "tool_search_call",
            "execution": "client",
            "call_id": callID,
            "status": starting ? "in_progress" : (item["status"] ?? "completed"),
            "arguments": arguments,
        ]
    }
}

package struct PreparedResponsesToolSearchRequest: Equatable, Sendable {
    package let upstreamBody: Data
    package let originalBody: Data
    package let contract: ResponsesClientToolSearchContract?
}
