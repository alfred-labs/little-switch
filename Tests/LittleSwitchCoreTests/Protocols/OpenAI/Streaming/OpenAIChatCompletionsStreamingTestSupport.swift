import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

func liveChatPrepared(
    targetModel: String = "glm-5.2",
    includeTools: Bool = true,
    toolStream: Bool = true
) throws -> PreparedResponsesChatCompletionsRequest {
    var body: [String: Any] = [
        "model": "little-switch-route",
        "input": "Find current information.",
        "stream": true,
    ]
    if includeTools {
        body["tools"] = [
            [
                "type": "function",
                "name": "web_search",
                "parameters": ["type": "object"],
            ],
            [
                "type": "function",
                "name": "weather",
                "parameters": ["type": "object"],
            ],
        ]
    }
    return try OpenAIResponsesChatCompletions.prepare(
        body: try chatJSONData(body),
        targetModel: targetModel,
        mode: .streaming(toolStream: toolStream)
    )
}

func interleavedChatFrames() throws -> [ServerSentEventFrame] {
    try [
        chatChunkFrame(choices: []),
        chatChunkFrame(choices: [
            chatChoice(
                delta: [
                    "role": "assistant",
                    "content": "FIRST ",
                    "reasoning_content": "private chain of thought",
                ]
            )
        ]),
        chatChunkFrame(choices: [
            chatChoice(delta: [
                "tool_calls": [
                    chatToolDelta(
                        index: 1,
                        id: "call_weather",
                        name: "weather",
                        arguments: #"{"city":""#
                    )
                ]
            ])
        ]),
        chatChunkFrame(choices: [
            chatChoice(delta: [
                "tool_calls": [
                    chatToolDelta(
                        index: 0,
                        id: "call_search",
                        name: "web_search",
                        arguments: #"{"query":"lat"#
                    )
                ]
            ])
        ]),
        chatChunkFrame(choices: [
            chatChoice(delta: [
                "tool_calls": [
                    chatToolDelta(index: 1, arguments: #"Paris"}"#)
                ]
            ])
        ]),
        chatChunkFrame(choices: [
            chatChoice(delta: [
                "tool_calls": [
                    chatToolDelta(index: 0, arguments: #"est Swift"}"#)
                ]
            ])
        ]),
        chatChunkFrame(choices: [
            chatChoice(delta: [:], finishReason: "length")
        ]),
        chatChunkFrame(
            choices: [],
            usage: [
                "prompt_tokens": 10,
                "completion_tokens": 5,
                "total_tokens": 15,
            ]
        ),
        chatDoneFrame(),
    ]
}

func simpleChatFrames(finishReason: String) throws -> [ServerSentEventFrame] {
    let initialDelta: [String: Any]
    if finishReason == "tool_calls" {
        initialDelta = [
            "role": "assistant",
            "tool_calls": [
                chatToolDelta(
                    index: 0,
                    id: "call_read",
                    name: "read_file",
                    arguments: #"{"path":"README.md"}"#
                )
            ],
        ]
    } else {
        initialDelta = ["role": "assistant", "content": "OK"]
    }
    return try [
        chatChunkFrame(choices: [chatChoice(delta: initialDelta)]),
        chatChunkFrame(choices: [
            chatChoice(delta: [:], finishReason: finishReason)
        ]),
        chatChunkFrame(
            choices: [],
            usage: [
                "prompt_tokens": 2,
                "completion_tokens": 1,
                "total_tokens": 3,
            ]
        ),
        chatDoneFrame(),
    ]
}

func chatChunkFrame(
    id: String = "chatcmpl_stream",
    created: Int = 100,
    model: String = "glm-5.2",
    choices: [[String: Any]],
    usage: [String: Any]? = nil
) throws -> ServerSentEventFrame {
    var object: [String: Any] = [
        "id": id,
        "object": "chat.completion.chunk",
        "created": created,
        "model": model,
        "choices": choices,
    ]
    if let usage {
        object["usage"] = usage
    }
    return ServerSentEventFrame(
        event: "untrusted-chat-label",
        data: try chatJSONData(object),
        terminal: false
    )
}

func chatDoneFrame() -> ServerSentEventFrame {
    ServerSentEventFrame(event: nil, data: Data(), terminal: true)
}

func chatChoice(
    index: Int = 0,
    delta: [String: Any],
    finishReason: String? = nil
) -> [String: Any] {
    [
        "index": index,
        "delta": delta,
        "finish_reason": finishReason ?? NSNull(),
    ]
}

func chatToolDelta(
    index: Int,
    id: String? = nil,
    name: String? = nil,
    arguments: String? = nil
) -> [String: Any] {
    var call: [String: Any] = ["index": index]
    if let id {
        call["id"] = id
        call["type"] = "function"
    }
    var function: [String: Any] = [:]
    if let name {
        function["name"] = name
    }
    if let arguments {
        function["arguments"] = arguments
    }
    if !function.isEmpty {
        call["function"] = function
    }
    return call
}

func chatJSONData(_ value: Any) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: value,
        options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
    )
}

func chatJSONObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

func chatSSEChunks(_ frames: [ServerSentEventFrame]) -> [Data] {
    frames.map { frame in
        if frame.terminal {
            return Data("data: [DONE]\n\n".utf8)
        }
        var wire = Data("data: ".utf8)
        wire.append(frame.data)
        wire.append(Data("\n\n".utf8))
        return wire
    }
}

func minimumChatFrameWireLimit(_ frames: [ServerSentEventFrame]) throws -> Int {
    let payloadFrames = frames.filter { !$0.terminal }
    let largestPayload = try #require(payloadFrames.map(\.data.count).max())
    let limit = max(largestPayload + Data("data: ".utf8).count, Data("data: [DONE]".utf8).count)
    #expect(payloadFrames.allSatisfy { $0.data.count < limit })
    #expect(payloadFrames.reduce(0) { $0 + $1.data.count } > limit)
    return limit
}

extension ResponsesProviderStreamEvent {
    var chatStartedResponseJSON: Data? {
        guard case .responseStarted(let responseJSON) = self else {
            return nil
        }
        return responseJSON
    }

    var chatPayloadJSON: Data? {
        switch self {
        case .responseStarted(let data), .outputItemAdded(_, let data),
            .outputItemDone(_, let data), .contentPartAdded(_, _, _, let data),
            .passthrough(_, let data), .terminal(_, let data):
            data
        default:
            nil
        }
    }
}
