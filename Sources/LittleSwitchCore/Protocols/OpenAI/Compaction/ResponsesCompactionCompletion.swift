import Foundation

extension ResponsesCompactionPlan {
    package func complete(responseBody: Data) throws -> ResponsesCompactionResult {
        let response = try ResponsesCompactionJSON.object(responseBody, error: .invalidResponse)
        guard response["status"] == nil || response["status"] as? String == "completed",
            let output = response["output"] as? [[String: Any]]
        else { throw ResponsesCompactionError.invalidResponse }
        let calls = output.filter { $0["type"] as? String == "function_call" }
        guard calls.count == 1, let call = calls.first,
            call["name"] as? String == "create_summary",
            call["namespace"] == nil || call["namespace"] is NSNull || (call["namespace"] as? String)?.isEmpty == true,
            let arguments = call["arguments"] as? String
        else { throw ResponsesCompactionError.invalidResponse }
        let selection = try ResponsesCompactionJSON.object(Data(arguments.utf8), error: .invalidResponse)
        guard Set(selection.keys) == ["summary", "retain_item_ids"],
            let summary = ResponsesCompactionJSON.nonempty(selection["summary"]),
            let references = selection["retain_item_ids"] as? [String]
        else { throw ResponsesCompactionError.invalidResponse }
        let known = Dictionary(uniqueKeysWithValues: items.indices.map { (ResponsesCompactionJSON.reference($0), $0) })
        var selected = Set<Int>()
        for reference in references {
            guard let index = known[reference], selected.insert(index).inserted else {
                throw ResponsesCompactionError.invalidResponse
            }
        }
        let indices = retention.retaining(selected.union(retainedStateIndices))
        var retained: [[String: Any]] = []
        for index in items.indices where indices.contains(index) {
            let item = try ResponsesCompactionJSON.object(items[index], error: .invalidResponse)
            guard item["type"] as? String != "compaction" || retainedStateIndices.contains(index) else {
                throw ResponsesCompactionError.invalidResponse
            }
            retained.append(item)
        }
        let payload: [String: Any] = [
            "type": "little_switch_compaction", "version": 1, "summary": summary, "retained": retained,
        ]
        let usage: ResponsesUsage
        do {
            usage = try OpenAIResponsesWebSearch.parseModelTurn(responseBody, privateToolName: nil).usage
        } catch {
            throw ResponsesCompactionError.invalidResponse
        }
        return ResponsesCompactionResult(
            itemJSON: try ResponsesCompactionJSON.data([
                "type": "compaction", "encrypted_content": try ResponsesCompactionJSON.text(payload),
            ]),
            usage: usage
        )
    }
}
