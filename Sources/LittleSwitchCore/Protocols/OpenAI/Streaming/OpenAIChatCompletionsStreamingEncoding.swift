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

func chatMessageDoneEvents(
    id: String,
    outputIndex: Int,
    text: String
) throws -> [ResponsesProviderStreamEvent] {
    let part: [String: Any] = [
        "type": "output_text",
        "text": text,
        "annotations": [],
        "logprobs": [],
    ]
    let item: [String: Any] = [
        "id": id,
        "type": "message",
        "status": "completed",
        "role": "assistant",
        "content": [part],
    ]
    return [
        .outputTextDone(
            outputIndex: outputIndex,
            contentIndex: 0,
            itemID: id,
            text: text
        ),
        .passthrough(
            type: "response.content_part.done",
            payloadJSON: try chatData([
                "type": "response.content_part.done",
                "output_index": outputIndex,
                "content_index": 0,
                "item_id": id,
                "part": part,
            ])
        ),
        .outputItemDone(
            outputIndex: outputIndex,
            itemJSON: try chatData(item)
        ),
    ]
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
