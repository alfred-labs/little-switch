import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

enum ResponsesSearchRefusalWire: CaseIterable, Sendable {
    case native
    case chatCompletions
}

enum ResponsesSearchRefusalMode: CaseIterable, Sendable {
    case buffered
    case streaming
    case jsonFallback

    var clientStreaming: Bool { self != .buffered }
    var providerStreaming: Bool { self == .streaming }
}

func refusalFunctionResponse(
    wire: ResponsesSearchRefusalWire,
    streaming: Bool,
    functionName: String = "collaboration__spawn_agent",
    arguments: String = #"{"task":"review"}"#
) throws -> HTTPClientResponse {
    let call = functionCallItem(
        id: "fc_refusal",
        callID: "call_refusal",
        name: functionName,
        arguments: arguments,
        status: "completed"
    )
    let terminal = responseObject(
        id: "resp_refusal",
        createdAt: 10,
        status: "completed",
        output: [call],
        usage: ResponsesUsage(inputTokens: 4, outputTokens: 2)
    )
    if !streaming {
        let body =
            switch wire {
            case .native:
                try #require(String(data: responseData(terminal), encoding: .utf8))
            case .chatCompletions:
                responsesModelResponse(id: "chatcmpl_refusal", output: [call])
            }
        return response(status: .ok, body: body)
    }

    let chunks: [String]
    switch wire {
    case .native:
        var added = call
        added["arguments"] = ""
        added["status"] = "in_progress"
        let frames = try [
            createdFrame(id: "resp_refusal", createdAt: 10),
            responsesFrame("response.output_item.added", ["output_index": 0, "item": added]),
            responsesFrame(
                "response.function_call_arguments.delta",
                ["output_index": 0, "item_id": "fc_refusal", "delta": arguments]
            ),
            responsesFrame(
                "response.function_call_arguments.done",
                ["output_index": 0, "item_id": "fc_refusal", "arguments": arguments]
            ),
            responsesFrame("response.output_item.done", ["output_index": 0, "item": call]),
            responsesFrame("response.completed", ["response": terminal]),
        ]
        chunks = [try #require(String(data: responsesGatewaySSE(frames), encoding: .utf8))]
    case .chatCompletions:
        let start: [String: Any] = [
            "id": "chatcmpl_refusal", "object": "chat.completion.chunk", "created": 10,
            "model": "provider-model",
            "choices": [
                [
                    "index": 0,
                    "delta": [
                        "role": "assistant",
                        "tool_calls": [
                            [
                                "index": 0, "id": "call_refusal", "type": "function",
                                "function": ["name": functionName, "arguments": arguments],
                            ]
                        ],
                    ],
                    "finish_reason": NSNull(),
                ]
            ],
        ]
        let done: [String: Any] = [
            "id": "chatcmpl_refusal", "object": "chat.completion.chunk", "created": 10,
            "model": "provider-model",
            "choices": [["index": 0, "delta": [:], "finish_reason": "tool_calls"]],
            "usage": ["prompt_tokens": 4, "completion_tokens": 2, "total_tokens": 6],
        ]
        chunks =
            try [start, done].map {
                "data: \(try #require(String(data: responseData($0), encoding: .utf8)))\n\n"
            } + ["data: [DONE]\n\n"]
    }
    return streamingResponse(status: .ok, headers: ["content-type": "text/event-stream"], chunks: chunks)
}
