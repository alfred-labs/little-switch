import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

struct FunctionEventFixture: Equatable {
    let itemID: String
    let callID: String
    let name: String
    let value: String
}

struct CompletedProviderObjects {
    let messageStart: [String: Any]
    let messageDone: [String: Any]
    let privateStart: [String: Any]
    let privateDone: [String: Any]
    let terminal: [String: Any]
}

func completedProviderFrames() throws -> [ServerSentEventFrame] {
    let objects = completedProviderObjects()
    return try completedMessageFrames(objects) + completedPrivateFunctionFrames(objects)
        + [responsesFrame("response.completed", ["response": objects.terminal])]
}

func completedProviderObjects() -> CompletedProviderObjects {
    let messageStart: [String: Any] = [
        "id": "msg_provider",
        "type": "message",
        "status": "in_progress",
        "role": "assistant",
        "content": [],
    ]
    let messageDone: [String: Any] = [
        "id": "msg_provider",
        "type": "message",
        "status": "completed",
        "role": "assistant",
        "content": [outputTextPart("FIRST answer")],
    ]
    let privateStart = functionCallItem(
        id: "fc_private",
        callID: "call_search",
        name: "web_search",
        arguments: "",
        status: "in_progress"
    )
    let privateDone = functionCallItem(
        id: "fc_private",
        callID: "call_search",
        name: "web_search",
        arguments: #"{"query":"latest Swift"}"#,
        status: "completed"
    )
    return CompletedProviderObjects(
        messageStart: messageStart,
        messageDone: messageDone,
        privateStart: privateStart,
        privateDone: privateDone,
        terminal: responseObject(
            id: "resp_provider",
            createdAt: 40,
            status: "completed",
            output: [messageDone, privateDone],
            usage: ResponsesUsage(inputTokens: 12, outputTokens: 7)
        )
    )
}

func completedMessageFrames(
    _ objects: CompletedProviderObjects
) throws -> [ServerSentEventFrame] {
    try [
        responsesFrame(
            "response.created",
            [
                "sequence_number": 900,
                "response": responseObject(
                    id: "resp_provider",
                    createdAt: 40,
                    status: "in_progress",
                    output: [],
                    usage: nil
                ),
            ],
            eventLabel: "provider.label.is.not.authoritative"
        ),
        responsesFrame(
            "response.in_progress",
            ["sequence_number": 901, "response": objects.terminal]
        ),
        responsesFrame(
            "response.output_item.added",
            ["output_index": 41, "item": objects.messageStart]
        ),
        responsesFrame(
            "response.content_part.added",
            [
                "output_index": 41,
                "content_index": 17,
                "item_id": "msg_provider",
                "part": outputTextPart(""),
            ]
        ),
        responsesFrame(
            "response.output_text.delta",
            [
                "output_index": 41,
                "content_index": 17,
                "item_id": "msg_provider",
                "delta": "FIRST",
                "logprobs": [],
            ]
        ),
        responsesFrame(
            "response.output_text.done",
            [
                "output_index": 41,
                "content_index": 17,
                "item_id": "msg_provider",
                "text": "FIRST answer",
                "logprobs": [],
            ]
        ),
        responsesFrame(
            "response.content_part.done",
            [
                "output_index": 41,
                "content_index": 17,
                "item_id": "msg_provider",
                "part": outputTextPart("FIRST answer"),
            ]
        ),
        responsesFrame(
            "response.output_item.done",
            ["output_index": 41, "item": objects.messageDone]
        ),
    ]
}

func completedPrivateFunctionFrames(
    _ objects: CompletedProviderObjects
) throws -> [ServerSentEventFrame] {
    try [
        responsesFrame(
            "response.output_item.added",
            ["output_index": 3, "item": objects.privateStart]
        ),
        responsesFrame(
            "response.function_call_arguments.delta",
            [
                "output_index": 3,
                "item_id": "fc_private",
                "delta": #"{"query":"latest "#,
            ]
        ),
        responsesFrame(
            "response.function_call_arguments.delta",
            [
                "output_index": 3,
                "item_id": "fc_private",
                "delta": #"Swift"}"#,
            ]
        ),
        responsesFrame(
            "response.function_call_arguments.done",
            [
                "output_index": 3,
                "item_id": "fc_private",
                "arguments": #"{"query":"latest Swift"}"#,
            ]
        ),
        responsesFrame(
            "response.output_item.done",
            ["output_index": 3, "item": objects.privateDone]
        ),
    ]
}

// Swift Format expands these bindings in the form SwiftLint rejects.
// swiftlint:disable pattern_matching_keywords
extension ResponsesProviderStreamEvent {
    var outputTextDelta: String? {
        guard case .outputTextDelta(_, _, _, let delta) = self else {
            return nil
        }
        return delta
    }

    var functionDelta: FunctionEventFixture? {
        guard case .functionArgumentsDelta(_, let itemID, let callID, let name, let delta) = self
        else {
            return nil
        }
        return FunctionEventFixture(itemID: itemID, callID: callID, name: name, value: delta)
    }

    var functionDone: FunctionEventFixture? {
        guard
            case .functionArgumentsDone(
                _,
                let
                    itemID,
                let
                    callID,
                let
                    name,
                let
                    arguments
            ) = self
        else {
            return nil
        }
        return FunctionEventFixture(
            itemID: itemID,
            callID: callID,
            name: name,
            value: arguments
        )
    }

    var passthroughType: String? {
        guard case .passthrough(let type, _) = self else {
            return nil
        }
        return type
    }

    var terminalStatus: ResponsesStreamTerminal? {
        guard case .terminal(let status, _) = self else {
            return nil
        }
        return status
    }
}
// swiftlint:enable pattern_matching_keywords

struct PublicResponseEvent {
    let name: String
    let payload: [String: Any]

    var sequenceNumber: Int? {
        payload["sequence_number"] as? Int
    }
}

func publicEvents(_ frames: [Data]) throws -> [PublicResponseEvent] {
    try frames.map { frame in
        let string = try #require(String(data: frame, encoding: .utf8))
        let lines = string.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count == 2,
            lines[0].hasPrefix("event: "),
            lines[1].hasPrefix("data: "),
            let payload = try JSONSerialization.jsonObject(
                with: Data(lines[1].dropFirst(6).utf8)
            ) as? [String: Any]
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return PublicResponseEvent(
            name: String(lines[0].dropFirst(7)),
            payload: payload
        )
    }
}

func strippedEnvelope(_ payload: [String: Any]) -> [String: Any] {
    var result = payload
    result.removeValue(forKey: "type")
    result.removeValue(forKey: "sequence_number")
    return result
}

func preparedWebSearchRequest() throws -> PreparedResponsesWebSearchRequest {
    let body = try responseData([
        "model": "little-switch-route",
        "input": "latest Swift",
        "stream": true,
        "tools": [
            ["type": "web_search"],
            [
                "type": "function",
                "name": "read_file",
                "parameters": ["type": "object"],
            ],
        ],
    ])
    return try #require(
        try OpenAIResponsesWebSearch.prepare(
            body: body,
            targetModel: "provider-model",
            configuration: .firecrawlCloud
        )
    )
}

func createdFrame(id: String, createdAt: Int) throws -> ServerSentEventFrame {
    try responsesFrame(
        "response.created",
        [
            "response": responseObject(
                id: id,
                createdAt: createdAt,
                status: "in_progress",
                output: [],
                usage: nil
            )
        ]
    )
}

func responsesFrame(
    _ type: String,
    _ payload: [String: Any],
    eventLabel: String? = nil
) throws -> ServerSentEventFrame {
    var object = payload
    object["type"] = type
    return ServerSentEventFrame(
        event: eventLabel ?? type,
        data: try responseData(object),
        terminal: false
    )
}

func responseObject(
    id: String,
    createdAt: Int,
    status: String,
    output: [[String: Any]],
    usage: ResponsesUsage?
) -> [String: Any] {
    var response: [String: Any] = [
        "id": id,
        "object": "response",
        "created_at": createdAt,
        "completed_at": status == "in_progress" ? NSNull() : createdAt + 1,
        "status": status,
        "model": "provider-model",
        "output": output,
        "tools": [["type": "function", "name": "web_search"]],
    ]
    if let usage {
        response["usage"] = [
            "input_tokens": usage.inputTokens,
            "output_tokens": usage.outputTokens,
            "total_tokens": usage.inputTokens + usage.outputTokens,
        ]
    } else {
        response["usage"] = NSNull()
    }
    return response
}

func functionCallItem(
    id: String,
    callID: String,
    name: String,
    arguments: String,
    status: String
) -> [String: Any] {
    [
        "id": id,
        "type": "function_call",
        "status": status,
        "call_id": callID,
        "name": name,
        "arguments": arguments,
    ]
}

func outputTextPart(_ text: String) -> [String: Any] {
    [
        "type": "output_text",
        "text": text,
        "annotations": [],
        "logprobs": [],
    ]
}

func responseData(_ value: Any) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: value,
        options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
    )
}
