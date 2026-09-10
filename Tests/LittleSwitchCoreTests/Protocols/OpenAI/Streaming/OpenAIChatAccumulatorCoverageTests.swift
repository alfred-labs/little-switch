import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Chat accumulator coverage")
struct OpenAIChatAccumulatorCoverageTests {
    @Test("Chunks reject malformed metadata, choices, roles, and content")
    // Every malformed chunk uses a fresh accumulator to isolate the boundary.
    func chunkShapeEdges() throws {
        let prepared = try liveChatPrepared()

        var missingChoices = OpenAIChatCompletionsAccumulator(prepared: prepared)
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try missingChoices.consume(coverageChatFrame([:]))
        }

        var missingMetadata = OpenAIChatCompletionsAccumulator(prepared: prepared)
        let metadataFreeFrame = ServerSentEventFrame(
            event: nil,
            data: try responseData(["choices": []]),
            terminal: false
        )
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try missingMetadata.consume(metadataFreeFrame)
        }

        var wrongDelta = OpenAIChatCompletionsAccumulator(prepared: prepared)
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try wrongDelta.consume(
                chatChunkFrame(choices: [
                    ["index": 0, "delta": "bad", "finish_reason": NSNull()]
                ]))
        }

        var secondChoice = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try secondChoice.consume(chatChunkFrame(choices: [chatChoice(delta: [:])]))
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try secondChoice.consume(
                chatChunkFrame(choices: [
                    chatChoice(index: 1, delta: [:])
                ]))
        }

        for delta: [String: Any] in [
            ["role": "user"],
            ["content": 1],
            ["tool_calls": "bad"],
        ] {
            var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
                _ = try accumulator.consume(
                    chatChunkFrame(choices: [
                        chatChoice(delta: delta)
                    ]))
            }
        }

        var afterUsage = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try afterUsage.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: ["content": "done"], finishReason: "stop")
            ]))
        _ = try afterUsage.consume(
            chatChunkFrame(
                choices: [],
                usage: ["prompt_tokens": 1, "completion_tokens": 1]
            ))
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try afterUsage.consume(chatChunkFrame(choices: []))
        }
    }

    @Test("Tool chunks reject malformed and non-contiguous calls")
    // This matrix covers every independently optional tool delta field.
    func toolEdges() throws {
        let prepared = try liveChatPrepared()
        let malformedCalls: [[String: Any]] = [
            [:],
            ["index": 0, "type": "private"],
            ["index": 0, "function": "bad"],
            ["index": 0, "id": "call", "type": "function", "function": [:]],
            [
                "index": 0, "id": "call", "type": "function",
                "function": ["name": "read", "arguments": 1],
            ],
        ]
        for call in malformedCalls {
            var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
                _ = try accumulator.consume(
                    chatChunkFrame(choices: [
                        chatChoice(delta: ["tool_calls": [call]])
                    ]))
            }
        }

        var overflow = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try overflow.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: ["content": "text"])
            ]))
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try overflow.consume(
                chatChunkFrame(choices: [
                    chatChoice(delta: [
                        "tool_calls": [
                            chatToolDelta(
                                index: Int.max,
                                id: "call",
                                name: "read",
                                arguments: "{}"
                            )
                        ]
                    ])
                ]))
        }

        var toolThenText = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try toolThenText.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "tool_calls": [
                        chatToolDelta(index: 0, id: "call", name: "read", arguments: "{}")
                    ]
                ])
            ]))
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try toolThenText.consume(
                chatChunkFrame(choices: [
                    chatChoice(delta: ["content": "not allowed"])
                ]))
        }

        var nonContiguous = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try nonContiguous.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "tool_calls": [
                        chatToolDelta(index: 1, id: "call", name: "read", arguments: "{}")
                    ]
                ])
            ]))
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try nonContiguous.consume(
                chatChunkFrame(choices: [
                    chatChoice(delta: [:], finishReason: "tool_calls")
                ]))
        }
    }
}

extension OpenAIChatAccumulatorCoverageTests {
    @Test("A provider cannot introduce multiple choices in one chunk")
    func multipleChoicesAreRejected() throws {
        let prepared = try liveChatPrepared()
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try accumulator.consume(
                chatChunkFrame(choices: [
                    chatChoice(index: 1, delta: ["role": "assistant", "content": "one"]),
                    chatChoice(index: 0, delta: ["role": "assistant", "content": "zero"]),
                ]))
        }
    }

    @Test("Finish reasons, usage, and DONE reject incomplete state")
    func terminalEdges() throws {
        let prepared = try liveChatPrepared()
        for finishReason in ["tool_calls", "network_error", "private"] {
            var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
                _ = try accumulator.consume(
                    chatChunkFrame(choices: [
                        chatChoice(delta: [:], finishReason: finishReason)
                    ]))
            }
        }

        var emptyStop = OpenAIChatCompletionsAccumulator(prepared: prepared)
        let events = try emptyStop.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: [:], finishReason: "stop")
            ]))
        #expect(events.contains { $0.chatPayloadJSON != nil })

        var prematureUsage = OpenAIChatCompletionsAccumulator(prepared: prepared)
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try prematureUsage.consume(
                chatChunkFrame(
                    choices: [],
                    usage: ["prompt_tokens": 1, "completion_tokens": 1]
                ))
        }

        var prematureDone = OpenAIChatCompletionsAccumulator(prepared: prepared)
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try prematureDone.consume(chatDoneFrame())
        }

        var unfinishedChoice = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try unfinishedChoice.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: ["content": "partial"])
            ]))
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try unfinishedChoice.consume(chatDoneFrame())
        }

        var incomplete = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try incomplete.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: ["content": "partial"], finishReason: "length")
            ]))
        _ = try incomplete.consume(
            chatChunkFrame(
                choices: [],
                usage: ["prompt_tokens": 1, "completion_tokens": 1]
            ))
        #expect(try !incomplete.consume(chatDoneFrame()).isEmpty)
    }

    @Test("Generated projection failures stay within the Chat error domain")
    func projectionFailure() throws {
        let valid = try liveChatPrepared()
        let invalid = PreparedResponsesChatCompletionsRequest(
            upstreamBody: valid.upstreamBody,
            originalBody: Data("[]".utf8),
            originalModel: valid.originalModel,
            streaming: valid.streaming
        )
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: invalid)
        _ = try accumulator.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: ["content": "text"], finishReason: "stop")
            ]))
        _ = try accumulator.consume(
            chatChunkFrame(
                choices: [],
                usage: ["prompt_tokens": 1, "completion_tokens": 1]
            ))
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try accumulator.consume(chatDoneFrame())
        }
    }
}

private func coverageChatFrame(_ additions: [String: Any]) throws -> ServerSentEventFrame {
    var payload: [String: Any] = [
        "id": "chat",
        "object": "chat.completion.chunk",
        "created": 1,
        "model": "provider",
    ]
    payload.merge(additions) { _, new in new }
    return ServerSentEventFrame(
        event: nil,
        data: try responseData(payload),
        terminal: false
    )
}
