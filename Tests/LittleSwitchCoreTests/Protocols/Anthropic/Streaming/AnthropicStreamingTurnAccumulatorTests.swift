import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic provider stream accumulator")
struct AnthropicStreamingTurnAccumulatorTests {
    @Test("Provider frames reconstruct a complete model turn")
    func providerTurnReconstruction() throws {
        var accumulator = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 64 * 1_024)
        var published: [AnthropicProviderStreamEvent] = []

        for frame in try realisticProviderFrames() {
            if let event = try accumulator.consume(frame) {
                published.append(event)
            }
        }

        let turn = try accumulator.finish()
        #expect(turn.id == "msg_provider")
        #expect(turn.stopReason == "tool_use")
        #expect(turn.stopSequenceJSON == Data(#""provider-sequence""#.utf8))
        #expect(turn.usage == AnthropicUsage(inputTokens: 12, outputTokens: 7))
        #expect(
            turn.webSearchCall
                == WebSearchToolCall(id: "toolu_search", query: "latest Swift")
        )
        #expect(published.contains(.ping))

        let content = try jsonArray(turn.contentJSON)
        #expect(content.count == 3)

        let text = try jsonDictionary(content[0])
        #expect(text["type"] as? String == "text")
        #expect(text["text"] as? String == "I should search.")
        let citations = try #require(text["citations"] as? [[String: Any]])
        #expect(citations.count == 1)
        #expect(citations[0]["type"] as? String == "web_search_result_location")
        #expect(citations[0]["url"] as? String == "https://swift.org/")

        let thinking = try jsonDictionary(content[1])
        #expect(thinking["type"] as? String == "thinking")
        #expect(thinking["thinking"] as? String == "Need current sources.")
        #expect(thinking["signature"] as? String == "opaque-signature")

        let tool = try jsonDictionary(content[2])
        #expect(tool["type"] as? String == "tool_use")
        #expect(tool["id"] as? String == "toolu_search")
        #expect(tool["name"] as? String == "web_search")
        #expect((tool["input"] as? [String: String]) == ["query": "latest Swift"])
    }

    @Test("A nullable citation start remains valid provider text")
    func nullableCitationStart() throws {
        let frames = try [
            providerFrame(
                "message_start",
                [
                    "type": "message_start",
                    "message": providerMessage(id: "msg_nullable_citations"),
                ]
            ),
            providerFrame(
                "content_block_start",
                [
                    "type": "content_block_start",
                    "index": 0,
                    "content_block": [
                        "type": "text",
                        "text": "answer",
                        "citations": NSNull(),
                    ],
                ]
            ),
            providerFrame(
                "content_block_stop",
                ["type": "content_block_stop", "index": 0]
            ),
            providerFrame(
                "message_delta",
                [
                    "type": "message_delta",
                    "delta": ["stop_reason": "end_turn", "stop_sequence": NSNull()],
                    "usage": ["output_tokens": 1],
                ]
            ),
            providerFrame("message_stop", ["type": "message_stop"]),
        ]

        var accumulator = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 8_192)
        for frame in frames {
            _ = try accumulator.consume(frame)
        }

        let content = try jsonArray(accumulator.finish().contentJSON)
        let text = try jsonDictionary(try #require(content.first))
        #expect(text["text"] as? String == "answer")
        #expect(text["citations"] is NSNull)
    }

    @Test("Provider lifecycle rejects malformed ordering and payloads")
    func providerLifecycleValidation() throws {
        let start = try providerFrame(
            "message_start",
            [
                "type": "message_start",
                "message": providerMessage(id: "msg_invalid"),
            ]
        )
        let blockStart = try providerFrame(
            "content_block_start",
            [
                "type": "content_block_start",
                "index": 0,
                "content_block": [
                    "type": "tool_use",
                    "id": "toolu_search",
                    "name": "web_search",
                    "input": [:],
                ],
            ]
        )

        var mismatchedIndex = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try mismatchedIndex.consume(start)
        _ = try mismatchedIndex.consume(blockStart)
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try mismatchedIndex.consume(
                providerFrame(
                    "content_block_delta",
                    [
                        "type": "content_block_delta",
                        "index": 1,
                        "delta": ["type": "input_json_delta", "partial_json": "{}"],
                    ]
                )
            )
        }

        var malformedInput = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try malformedInput.consume(start)
        _ = try malformedInput.consume(blockStart)
        _ = try malformedInput.consume(
            providerFrame(
                "content_block_delta",
                [
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": [
                        "type": "input_json_delta",
                        "partial_json": #"{"query":"unterminated"#,
                    ],
                ]
            )
        )
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try malformedInput.consume(
                providerFrame(
                    "content_block_stop",
                    ["type": "content_block_stop", "index": 0]
                )
            )
        }

        var incompleteBlock = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try incompleteBlock.consume(start)
        _ = try incompleteBlock.consume(blockStart)
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try incompleteBlock.finish()
        }

        var incompleteMessage = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try incompleteMessage.consume(start)
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try incompleteMessage.finish()
        }
    }

    @Test("Provider events validate event labels, JSON types, and turn bounds")
    func providerEnvelopeAndBounds() throws {
        var mismatchedType = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 4_096)
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try mismatchedType.consume(
                providerFrame(
                    "message_start",
                    ["type": "message_stop"]
                )
            )
        }

        var invalidKnownEvent = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 4_096)
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try invalidKnownEvent.consume(
                ServerSentEventFrame(
                    event: "content_block_delta",
                    data: Data(#"{"type":"content_block_delta","index":0}"#.utf8),
                    terminal: false
                )
            )
        }

        var bounded = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 32)
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try bounded.consume(
                providerFrame(
                    "message_start",
                    [
                        "type": "message_start",
                        "message": providerMessage(
                            id: "msg_far_too_large_for_the_configured_turn_bound"
                        ),
                    ]
                )
            )
        }

        var controlFrames = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 0)
        #expect(
            try controlFrames.consume(providerFrame("ping", ["type": "ping"]))
                == .ping
        )
        #expect(
            try controlFrames.consume(
                providerFrame("future_control", ["type": "future_control"])
            ) == nil
        )
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try controlFrames.consume(
                ServerSentEventFrame(event: nil, data: Data(), terminal: true)
            )
        }
    }

}

extension AnthropicStreamingTurnAccumulatorTests {
    @Test("Provider blocks may interleave while preserving start order")
    func interleavedProviderBlocks() throws {
        let frames = try [
            providerFrame(
                "message_start",
                [
                    "type": "message_start",
                    "message": providerMessage(id: "msg_interleaved", inputTokens: 2),
                ]
            ),
            providerFrame(
                "content_block_start",
                [
                    "type": "content_block_start",
                    "index": 0,
                    "content_block": ["type": "text", "text": ""],
                ]
            ),
            providerFrame(
                "content_block_start",
                [
                    "type": "content_block_start",
                    "index": 1,
                    "content_block": ["type": "thinking", "thinking": ""],
                ]
            ),
            providerFrame(
                "content_block_delta",
                [
                    "type": "content_block_delta",
                    "index": 1,
                    "delta": ["type": "thinking_delta", "thinking": "think"],
                ]
            ),
            providerFrame(
                "content_block_delta",
                [
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": ["type": "text_delta", "text": "answer"],
                ]
            ),
            providerFrame(
                "content_block_stop",
                ["type": "content_block_stop", "index": 1]
            ),
            providerFrame(
                "content_block_stop",
                ["type": "content_block_stop", "index": 0]
            ),
            providerFrame(
                "message_delta",
                [
                    "type": "message_delta",
                    "delta": ["stop_reason": "end_turn", "stop_sequence": NSNull()],
                    "usage": ["output_tokens": 3],
                ]
            ),
            providerFrame("message_stop", ["type": "message_stop"]),
        ]
        var accumulator = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 8_192)
        for frame in frames {
            _ = try accumulator.consume(frame)
        }
        let content = try jsonArray(accumulator.finish().contentJSON)
        #expect(
            try content.map { try jsonDictionary($0)["type"] as? String }
                == ["text", "thinking"]
        )
        #expect(try jsonDictionary(content[0])["text"] as? String == "answer")
        #expect(try jsonDictionary(content[1])["thinking"] as? String == "think")
    }

    @Test("Unknown provider block deltas publish without changing reconstruction")
    func unknownProviderBlockDelta() throws {
        let unknownDelta = try providerFrame(
            "content_block_delta",
            [
                "type": "content_block_delta",
                "index": 0,
                "delta": [
                    "type": "future_text_metadata_delta",
                    "metadata": ["source": "provider"],
                ],
            ]
        )
        let frames = try [
            providerFrame(
                "message_start",
                [
                    "type": "message_start",
                    "message": providerMessage(id: "msg_unknown_delta", inputTokens: 2),
                ]
            ),
            providerFrame(
                "content_block_start",
                [
                    "type": "content_block_start",
                    "index": 0,
                    "content_block": ["type": "text", "text": ""],
                ]
            ),
            unknownDelta,
            providerFrame(
                "content_block_delta",
                [
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": ["type": "text_delta", "text": "answer"],
                ]
            ),
            providerFrame(
                "content_block_stop",
                ["type": "content_block_stop", "index": 0]
            ),
            providerFrame(
                "message_delta",
                [
                    "type": "message_delta",
                    "delta": ["stop_reason": "end_turn", "stop_sequence": NSNull()],
                    "usage": ["output_tokens": 3],
                ]
            ),
            providerFrame("message_stop", ["type": "message_stop"]),
        ]

        var accumulator = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 8_192)
        var publishedUnknown: AnthropicProviderStreamEvent?
        for (offset, frame) in frames.enumerated() {
            let event = try accumulator.consume(frame)
            if offset == 2 {
                publishedUnknown = event
            }
        }

        let unknownPayload = try anthropicWebSearchObject(unknownDelta.data)
        let unknownJSON = try #require(unknownPayload["delta"] as? [String: Any])
        #expect(
            publishedUnknown
                == .contentDelta(
                    index: 0,
                    deltaJSON: try anthropicWebSearchData(unknownJSON)
                )
        )
        let content = try jsonArray(accumulator.finish().contentJSON)
        #expect(try jsonDictionary(content[0])["text"] as? String == "answer")

        var mismatch = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try mismatch.consume(frames[0])
        _ = try mismatch.consume(frames[1])
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try mismatch.consume(
                providerFrame(
                    "content_block_delta",
                    [
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": ["type": "thinking_delta", "thinking": "wrong block"],
                    ]
                )
            )
        }
    }
}
