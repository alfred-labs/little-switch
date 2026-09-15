import Foundation
import LittleSwitchCommon
import LittleSwitchWire

extension ResponsesCompactionPlan {
    package func complete(
        responseBody: Data,
        maximumBytes: Int = 64 * 1_024 * 1_024
    ) throws -> ResponsesCompactionResult {
        let response = try ResponsesCompactionJSON.object(responseBody, error: .invalidResponse)
        guard
            response[OpenAIResponsesResponse.Key.status.rawValue] == nil
                || response[OpenAIResponsesResponse.Key.status.rawValue] as? String
                    == OpenAIResponsesStatus.completed.rawValue,
            let output = response[OpenAIResponsesResponse.Key.output.rawValue] as? [[String: Any]]
        else { throw ResponsesCompactionError.invalidResponse }
        let calls = output.filter {
            $0[OpenAIResponsesUserMessage.Key.type.rawValue] as? String
                == OpenAIResponsesFunctionCallType.functionCall.rawValue
        }
        guard calls.count == 1, let call = calls.first,
            call[OpenAIResponsesFunctionCall.Key.name.rawValue] as? String == "create_summary",
            call[OpenAIResponsesFunctionCall.Key.namespace.rawValue] == nil
                || call[OpenAIResponsesFunctionCall.Key.namespace.rawValue] is NSNull
                || (call[OpenAIResponsesFunctionCall.Key.namespace.rawValue] as? String)?.isEmpty == true,
            let arguments = call[OpenAIResponsesFunctionCall.Key.arguments.rawValue] as? String
        else { throw ResponsesCompactionError.invalidSelection("expected exactly one create_summary function call") }
        guard let selection = try? ResponsesCompactionJSON.object(Data(arguments.utf8), error: .invalidResponse)
        else {
            throw ResponsesCompactionError.invalidSelection("the create_summary arguments are not a JSON object")
        }
        guard
            Set(selection.keys) == [
                ResponsesCompactionContract.Selection.summary.rawValue,
                ResponsesCompactionContract.Selection.retainedIDs.rawValue,
            ],
            let summary = ResponsesCompactionJSON.nonempty(
                selection[ResponsesCompactionContract.Selection.summary.rawValue]),
            let references = selection[ResponsesCompactionContract.Selection.retainedIDs.rawValue] as? [String]
        else {
            throw ResponsesCompactionError.invalidSelection(
                "the selection needs a nonempty summary and a retain_item_ids array")
        }
        let known = Dictionary(uniqueKeysWithValues: items.indices.map { (ResponsesCompactionJSON.reference($0), $0) })
        var selected = Set<Int>()
        for reference in references {
            guard let index = known[reference], !omittedIndices.contains(index), selected.insert(index).inserted else {
                throw ResponsesCompactionError.invalidSelection(
                    "retain_item_ids must name distinct, still-present transcript items")
            }
        }
        let indices = retention.retaining(selected.union(retainedStateIndices))
        var retained: [[String: Any]] = []
        for index in items.indices where indices.contains(index) {
            let item = try ResponsesCompactionJSON.object(items[index], error: .invalidResponse)
            guard
                item[OpenAIResponsesUserMessage.Key.type.rawValue] as? String
                    != ResponsesCompactionContract.Kind.compaction.rawValue || retainedStateIndices.contains(index)
            else {
                throw ResponsesCompactionError.invalidSelection("opaque compaction state cannot be retained")
            }
            retained.append(item)
        }
        let payload: [String: Any] = [
            ResponsesCompactionContract.Payload.type.rawValue: ResponsesCompactionContract.Kind.owned.rawValue,
            ResponsesCompactionContract.Payload.version.rawValue: 1,
            ResponsesCompactionContract.Payload.summary.rawValue: omittedIndices.isEmpty
                ? summary : ResponsesCompactionPlan.omissionNotice(count: omittedIndices.count) + "\n\n" + summary,
            ResponsesCompactionContract.Payload.retained.rawValue: retained,
        ]
        let usage: ResponsesUsage
        do {
            usage = try OpenAIResponsesWebSearch.parseModelTurn(responseBody, privateToolName: nil).usage
        } catch {
            throw ResponsesCompactionError.invalidResponse
        }
        let itemJSON = try ResponsesCompactionJSON.data([
            OpenAIResponsesUserMessage.Key.type.rawValue: ResponsesCompactionContract.Kind.compaction.rawValue,
            ResponsesCompactionContract.Payload.encryptedContent.rawValue: try ResponsesCompactionJSON.text(payload),
        ])
        guard itemJSON.count <= maximumBytes else { throw ResponsesCompactionError.responseTooLarge }
        return ResponsesCompactionResult(itemJSON: itemJSON, usage: usage)
    }
}
