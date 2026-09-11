import Foundation

/// Lifecycle of a buffered chat completions turn.
package enum ChatCompletionAccumulatorPhase: Sendable {
    case open
    case terminal
    case finished
}

func chatStartedResponseJSON(
    responseID: String,
    created: Int,
    originalModel: String
) throws -> Data {
    try chatData([
        "id": responseID,
        "object": "response",
        "created_at": created,
        "status": "in_progress",
        "model": originalModel,
        "output": [],
        "usage": NSNull(),
    ])
}

func chatMessageStartEvents(
    id: String,
    outputIndex: Int
) throws -> [ResponsesProviderStreamEvent] {
    let item: [String: Any] = [
        "id": id,
        "type": "message",
        "status": "in_progress",
        "role": "assistant",
        "content": [],
    ]
    let part: [String: Any] = [
        "type": "output_text",
        "text": "",
        "annotations": [],
        "logprobs": [],
    ]
    return [
        .outputItemAdded(
            outputIndex: outputIndex,
            itemJSON: try chatData(item)
        ),
        .contentPartAdded(
            outputIndex: outputIndex,
            contentIndex: 0,
            itemID: id,
            partJSON: try chatData(part)
        ),
    ]
}

func chatMessageDoneEvents(_ message: ChatCompletionMessageState) throws -> [ResponsesProviderStreamEvent] {
    var parts: [Int: [String: Any]] = [:]
    var events: [ResponsesProviderStreamEvent] = []
    if let text = message.completedText {
        parts[message.textIndex] = ["type": "output_text", "text": text, "annotations": [], "logprobs": []]
        events.append(
            .outputTextDone(
                outputIndex: message.outputIndex, contentIndex: message.textIndex, itemID: message.id, text: text))
    }
    if let index = message.refusalIndex {
        let refusal = message.refusal.joined()
        parts[index] = ["type": "refusal", "refusal": refusal]
        events.append(
            .passthrough(
                type: "response.refusal.done",
                payloadJSON: try chatData([
                    "type": "response.refusal.done", "output_index": message.outputIndex, "content_index": index,
                    "item_id": message.id, "refusal": refusal,
                ])))
    }
    for (index, part) in parts.sorted(by: { $0.key < $1.key }) {
        events.append(
            .passthrough(
                type: "response.content_part.done",
                payloadJSON: try chatData([
                    "type": "response.content_part.done", "output_index": message.outputIndex, "content_index": index,
                    "item_id": message.id, "part": part,
                ])))
    }
    let content = parts.sorted { $0.key < $1.key }.map(\.value)
    events.append(
        .outputItemDone(
            outputIndex: message.outputIndex,
            itemJSON: try chatData([
                "id": message.id, "type": "message", "status": "completed", "role": "assistant",
                "content": content,
            ])))
    return events
}

func chatFunctionItem(
    itemID: String,
    callID: String,
    name: String,
    arguments: String,
    status: String,
    binding: ResponsesToolNamespaces.Binding? = nil
) -> [String: Any] {
    var item: [String: Any] = [
        "id": itemID,
        "type": "function_call",
        "status": status,
        "call_id": callID,
        "name": binding?.name ?? name,
        "arguments": status == "completed" ? arguments : "",
    ]
    if let binding {
        item["namespace"] = binding.namespace
    }
    return item
}

func chatFinishReason(_ value: Any?) throws -> String? {
    guard let value, !(value is NSNull) else {
        return nil
    }
    guard let value = value as? String, !value.isEmpty else {
        throw OpenAIResponsesChatCompletions.Error.invalidResponse
    }
    return value
}

func nonemptyChatString(_ value: Any?) -> String? {
    guard let value = value as? String, !value.isEmpty else {
        return nil
    }
    return value
}

func nonnegativeChatIndex(_ value: Any?) -> Int? {
    guard let value = value as? Int, value >= 0 else {
        return nil
    }
    return value
}

func chatObject(_ data: Data) throws -> [String: Any] {
    do {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        return object
    } catch let error as OpenAIResponsesChatCompletions.Error {
        throw error
    } catch {
        throw OpenAIResponsesChatCompletions.Error.invalidResponse
    }
}

func chatData(_ value: Any) throws -> Data {
    guard validChatJSONValue(value) else {
        throw OpenAIResponsesChatCompletions.Error.invalidResponse
    }
    return try JSONSerialization.data(
        withJSONObject: value,
        options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
    )
}

private func validChatJSONValue(_ value: Any) -> Bool {
    if JSONSerialization.isValidJSONObject(value) {
        return true
    }
    if value is NSNull || value is String {
        return true
    }
    guard let number = value as? NSNumber else {
        return false
    }
    return number.doubleValue.isFinite
}
