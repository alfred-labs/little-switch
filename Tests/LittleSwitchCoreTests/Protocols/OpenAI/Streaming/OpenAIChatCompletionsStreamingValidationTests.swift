import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

extension OpenAIChatCompletionsStreamingTests {
    @Test("Malformed chunks and unstable response metadata are rejected")
    func malformedChunks() throws {
        let prepared = try liveChatPrepared()
        var malformed = OpenAIChatCompletionsAccumulator(prepared: prepared)
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try malformed.consume(
                ServerSentEventFrame(event: nil, data: Data("{".utf8), terminal: false)
            )
        }

        var unstable = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try unstable.consume(chatChunkFrame(choices: []))
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try unstable.consume(
                chatChunkFrame(id: "chatcmpl_changed", choices: [])
            )
        }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try unstable.consume(
                chatChunkFrame(choices: [chatChoice(index: -1, delta: [:])])
            )
        }
    }

    @Test("Interleaved tool calls require stable IDs and names")
    func unstableToolMetadata() throws {
        let prepared = try liveChatPrepared()
        for changed in [
            chatToolDelta(index: 0, id: "call_changed", arguments: "}"),
            chatToolDelta(index: 0, name: "write_file", arguments: "}"),
        ] {
            var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
            _ = try accumulator.consume(
                chatChunkFrame(choices: [
                    chatChoice(delta: [
                        "tool_calls": [
                            chatToolDelta(
                                index: 0,
                                id: "call_read",
                                name: "read_file",
                                arguments: "{"
                            )
                        ]
                    ])
                ])
            )
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
                _ = try accumulator.consume(
                    chatChunkFrame(choices: [
                        chatChoice(delta: ["tool_calls": [changed]])
                    ])
                )
            }
        }
    }

    @Test("DONE requires finish reason and terminal usage exactly once")
    func incompleteLifecycle() throws {
        let prepared = try liveChatPrepared()
        var missingUsage = OpenAIChatCompletionsAccumulator(prepared: prepared)
        for frame in try [
            chatChunkFrame(choices: [
                chatChoice(delta: ["content": "partial"])
            ]),
            chatChunkFrame(choices: [
                chatChoice(delta: [:], finishReason: "stop")
            ]),
        ] {
            _ = try missingUsage.consume(frame)
        }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try missingUsage.consume(chatDoneFrame())
        }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try missingUsage.finish()
        }

        var afterFinish = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try afterFinish.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: ["content": "done"], finishReason: "stop")
            ])
        )
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try afterFinish.consume(
                chatChunkFrame(choices: [chatChoice(delta: ["content": "late"])])
            )
        }
    }

    @Test("Stream accumulation is bounded and terminal is unique")
    func boundsAndTerminalUniqueness() throws {
        let prepared = try liveChatPrepared()
        var bounded = OpenAIChatCompletionsAccumulator(prepared: prepared)
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try bounded.consume(
                ServerSentEventFrame(
                    event: nil,
                    data: Data(repeating: 0x20, count: 9 * 1_024 * 1_024),
                    terminal: false
                )
            )
        }

        var completed = OpenAIChatCompletionsAccumulator(prepared: prepared)
        for frame in try simpleChatFrames(finishReason: "stop") {
            _ = try completed.consume(frame)
        }
        #expect(try completed.finish().id == "resp_chatcmpl_stream")
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try completed.finish()
        }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try completed.consume(chatDoneFrame())
        }
    }

    @Test("Configured turn limit accepts the exact total and rejects cumulative overflow")
    func configuredCumulativeBounds() throws {
        let prepared = try liveChatPrepared()
        let frames = try simpleChatFrames(finishReason: "stop")
        let payloadFrames = frames.filter { !$0.terminal }
        let exactLimit = payloadFrames.reduce(0) { $0 + $1.data.count }
        #expect(payloadFrames.count > 1)
        #expect(payloadFrames.allSatisfy { $0.data.count < exactLimit })

        var exact = OpenAIChatCompletionsAccumulator(
            prepared: prepared,
            maximumTurnBytes: exactLimit
        )
        for frame in frames {
            _ = try exact.consume(frame)
        }
        #expect(try exact.finish().id == "resp_chatcmpl_stream")

        var overflow = OpenAIChatCompletionsAccumulator(
            prepared: prepared,
            maximumTurnBytes: exactLimit - 1
        )
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            for frame in frames {
                _ = try overflow.consume(frame)
            }
        }
    }
}

extension OpenAIChatCompletionsStreamingTests {
    /// SGLang's closing delta carries explicit JSON nulls ("role": null,
    /// "tool_calls": null) after the answer text. JSONSerialization surfaces
    /// them as NSNull, and a null must read as an absent field, exactly like
    /// the null "content" of keep-alive deltas — not as a role that fails the
    /// assistant check. Captured from a live glm-5.3-flash burst that died as
    /// invalidProviderStream("invalidResponse") after this exact frame.
    @Test("SGLang null-valued delta fields parse as absent, not as failures")
    func sglangNullDeltaFieldsParse() throws {
        let prepared = try liveChatPrepared()
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        let frames = try [
            chatChunkFrame(
                id: "3cf518d4f317480fa0d7057c7a7a9812",
                created: 1_788_520_787,
                model: "glm-5.3-flash",
                choices: [
                    chatChoice(delta: [
                        "reasoning_content": NSNull(),
                        "role": "assistant",
                        "content": "",
                    ])
                ]
            ),
            chatChunkFrame(
                id: "3cf518d4f317480fa0d7057c7a7a9812",
                created: 1_788_520_787,
                model: "glm-5.3-flash",
                choices: [chatChoice(delta: ["reasoning_content": "The"])]
            ),
            chatChunkFrame(
                id: "3cf518d4f317480fa0d7057c7a7a9812",
                created: 1_788_520_787,
                model: "glm-5.3-flash",
                choices: [
                    chatChoice(delta: [
                        "role": NSNull(),
                        "content": "OK",
                        "reasoning_content": NSNull(),
                        "tool_calls": NSNull(),
                    ])
                ]
            ),
            chatChunkFrame(
                id: "3cf518d4f317480fa0d7057c7a7a9812",
                created: 1_788_520_787,
                model: "glm-5.3-flash",
                choices: [
                    chatChoice(
                        delta: [
                            "role": NSNull(),
                            "content": NSNull(),
                            "reasoning_content": NSNull(),
                            "tool_calls": NSNull(),
                        ],
                        finishReason: "stop"
                    )
                ]
            ),
            chatChunkFrame(
                id: "3cf518d4f317480fa0d7057c7a7a9812",
                created: 1_788_520_787,
                model: "glm-5.3-flash",
                choices: [],
                usage: [
                    "prompt_tokens": 315,
                    "total_tokens": 332,
                    "completion_tokens": 17,
                ] as [String: Any]
            ),
        ]
        for frame in frames {
            _ = try accumulator.consume(frame)
        }
        _ = try accumulator.consume(chatDoneFrame())
        let turn = try accumulator.finish()
        #expect(turn.usage.totalTokens == 332)
    }
}

extension OpenAIChatCompletionsStreamingTests {
    /// Replays the exact four chunks of a recorded failed Desktop burst
    /// (xlarge/chat, post NSNull fix, still dying as invalidProviderStream).
    /// A plain reasoning preamble: role assistant, empty content, then three
    /// reasoning deltas — nothing exotic, yet the gateway threw.
    @Test("Recorded Desktop reasoning preamble parses")
    func recordedDesktopPreambleParses() throws {
        let prepared = try liveChatPrepared()
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        let frames = try [
            chatChunkFrame(
                id: "70219040e9cc462f9b5ed038ccc52714",
                created: 1_788_522_105,
                model: "glm-5.3-flash",
                choices: [
                    chatChoice(delta: [
                        "reasoning_content": NSNull(),
                        "role": "assistant",
                        "content": "",
                    ])
                ]
            ),
            chatChunkFrame(
                id: "70219040e9cc462f9b5ed038ccc52714",
                created: 1_788_522_105,
                model: "glm-5.3-flash",
                choices: [chatChoice(delta: ["reasoning_content": "The"])]
            ),
            chatChunkFrame(
                id: "70219040e9cc462f9b5ed038ccc52714",
                created: 1_788_522_105,
                model: "glm-5.3-flash",
                choices: [chatChoice(delta: ["reasoning_content": " user"])]
            ),
            chatChunkFrame(
                id: "70219040e9cc462f9b5ed038ccc52714",
                created: 1_788_522_106,
                model: "glm-5.3-flash",
                choices: [chatChoice(delta: ["reasoning_content": " just"])]
            ),
        ]
        for frame in frames {
            _ = try accumulator.consume(frame)
        }
    }
}

extension OpenAIChatCompletionsStreamingTests {
    /// SGLang/OpenAI continuation fragments repeat the tool call slot with
    /// explicit null id and name — only index and arguments progress. A null
    /// means "unchanged", not "a different id": captured from a live xlarge
    /// burst that died as invalidProviderStream on exactly this pair.
    @Test("Tool-call continuation with null id and name keeps the call")
    func toolCallContinuationNullsKeepIdentity() throws {
        let prepared = try liveChatPrepared()
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        let start = try chatChunkFrame(
            id: "ca21518208484dae9538b9c6c74ededc",
            created: 1_788_523_055,
            model: "glm-5.3-flash",
            choices: [
                chatChoice(delta: [
                    "role": NSNull(),
                    "content": NSNull(),
                    "reasoning_content": NSNull(),
                    "tool_calls": [
                        [
                            "id": "call_2668ec019aca4b809a703fcb",
                            "index": 0,
                            "type": "function",
                            "function": ["name": "exec_command", "arguments": ""],
                        ] as [String: Any]
                    ],
                ])
            ]
        )
        let continuation = try chatChunkFrame(
            id: "ca21518208484dae9538b9c6c74ededc",
            created: 1_788_523_055,
            model: "glm-5.3-flash",
            choices: [
                chatChoice(delta: [
                    "role": NSNull(),
                    "content": NSNull(),
                    "reasoning_content": NSNull(),
                    "tool_calls": [
                        [
                            "id": NSNull(),
                            "index": 0,
                            "type": "function",
                            "function": ["name": NSNull(), "arguments": "{"],
                        ] as [String: Any]
                    ],
                ])
            ]
        )
        _ = try accumulator.consume(start)
        _ = try accumulator.consume(continuation)
    }
}
