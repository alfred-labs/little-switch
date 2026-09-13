import Foundation
import LittleSwitchWire

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
    try WireCodec.encode(
        OpenAIResponsesResponse(
            createdAt: JSONNumber(created),
            id: responseID,
            object: .response,
            output: [],
            status: .inProgress,
            usage: .null,
            additionalFields: ["model": .string(originalModel)]
        ))
}

func chatMessageStartEvents(
    id: String,
    outputIndex: Int
) throws -> [ResponsesProviderStreamEvent] {
    let item = OpenAIResponsesMessage(
        content: [], id: id, role: .assistant, status: .value(.inProgress), type: .message)
    let part = OpenAIResponsesOutputText(
        annotations: .value([]), logprobs: .value([]), text: "", type: .outputText)
    return [
        .outputItemAdded(
            outputIndex: outputIndex,
            itemJSON: try WireCodec.encode(item)
        ),
        .contentPartAdded(
            outputIndex: outputIndex,
            contentIndex: 0,
            itemID: id,
            partJSON: try WireCodec.encode(part)
        ),
    ]
}

func chatMessageDoneEvents(_ message: ChatCompletionMessageState) throws -> [ResponsesProviderStreamEvent] {
    var parts: [Int: OpenAIResponsesContentPart] = [:]
    var events: [ResponsesProviderStreamEvent] = []
    if let text = message.completedText {
        parts[message.textIndex] = .outputText(
            OpenAIResponsesOutputText(
                annotations: .value([]), logprobs: .value([]), text: text, type: .outputText))
        events.append(
            .outputTextDone(
                outputIndex: message.outputIndex, contentIndex: message.textIndex, itemID: message.id, text: text))
    }
    if let index = message.refusalIndex {
        let refusal = message.refusal.joined()
        parts[index] = .refusal(OpenAIResponsesRefusal(refusal: refusal, type: .refusal))
        events.append(
            .passthrough(
                type: OpenAIResponsesRefusalDoneEventType.responseRefusalDone.rawValue,
                payloadJSON: try WireCodec.encode(
                    OpenAIResponsesRefusalDoneEvent(
                        contentIndex: JSONNumber(index),
                        itemId: message.id,
                        outputIndex: JSONNumber(message.outputIndex),
                        refusal: refusal,
                        type: .responseRefusalDone
                    ))))
    }
    for (index, part) in parts.sorted(by: { $0.key < $1.key }) {
        events.append(
            .passthrough(
                type: OpenAIContentPartDoneType.responseContentPartDone.rawValue,
                payloadJSON: try WireCodec.encode(
                    OpenAIContentPartDone(
                        contentIndex: JSONNumber(index),
                        itemId: message.id,
                        outputIndex: JSONNumber(message.outputIndex),
                        part: part.wireJSON(),
                        type: .responseContentPartDone
                    ))))
    }
    let content = parts.sorted { $0.key < $1.key }.map(\.value)
    events.append(
        .outputItemDone(
            outputIndex: message.outputIndex,
            itemJSON: try WireCodec.encode(
                OpenAIResponsesMessage(
                    content: content, id: message.id, role: .assistant, status: .value(.completed), type: .message
                ))))
    return events
}

func chatFunctionItem(
    itemID: String,
    callID: String,
    name: String,
    arguments: String,
    status: OpenAIResponsesFunctionCallStatus,
    binding: ResponsesToolNamespaces.Binding? = nil
) -> OpenAIResponsesFunctionCall {
    OpenAIResponsesFunctionCall(
        arguments: status == .completed ? arguments : "",
        callId: callID,
        id: itemID,
        name: binding?.name ?? name,
        namespace: binding.map { .value($0.namespace) } ?? .absent,
        status: .value(status),
        type: .functionCall)
}

func chatData(_ value: Any) throws -> Data {
    do {
        return try WireJSONCompatibility.data(value)
    } catch {
        throw OpenAIResponsesChatCompletions.Error.invalidResponse
    }
}
