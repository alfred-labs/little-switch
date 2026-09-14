import Foundation
import LittleSwitchCommon
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic provider stream terminal state")
struct AnthropicStreamingTerminalStateTests {
    @Test("Unknown terminal reasons survive null updates without acquiring known semantics")
    func unknownTerminalReasonRoundTrips() throws {
        var state = AnthropicTerminalDeltaState()
        state.apply(
            AnthropicMessageDelta(
                stopReason: .value(.unknown("future_reason")), stopSequence: .value("marker")
            ))
        state.apply(AnthropicMessageDelta(stopReason: .null, stopSequence: .null))
        var message = AnthropicMessage(content: [], id: "msg", usage: [:])
        state.apply(to: &message)
        #expect(message.stopReason.value?.rawValue == "future_reason")
        #expect(message.stopSequence.value == .string("marker"))
    }

    @Test("Highly fragmented terminal updates preserve order and drop unknown state")
    func highlyFragmentedTerminalState() throws {
        let fragmentCount = 1_024
        var accumulator = AnthropicStreamingTurnAccumulator(
            maximumTurnBytes: 8 * 1_024 * 1_024
        )
        var message = providerMessage(id: "msg_terminal_state", inputTokens: 11)
        message["usage"] = [
            "input_tokens": 11,
            "output_tokens": 0,
            "cache_creation_input_tokens": 2,
            "cache_read_input_tokens": 3,
            "cache_creation": [
                "ephemeral_1h_input_tokens": 5,
                "ephemeral_5m_input_tokens": 7,
            ],
            "service_tier": "standard",
        ]
        _ = try accumulator.consume(
            providerFrame(
                "message_start",
                ["type": "message_start", "message": message]
            )
        )

        var publishedOutputTokens: [Int] = []
        var finalPublishedDelta: [String: Any] = [:]
        for index in 0..<fragmentCount {
            var delta: [String: Any] = [
                "stop_reason": NSNull(),
                "stop_sequence": NSNull(),
                "provider_internal_\(index)": ["opaque": "value-\(index)"],
            ]
            if index == 0 {
                delta["stop_reason"] = "pause_turn"
                delta["stop_sequence"] = "first-sequence"
            }
            if index == fragmentCount - 1 {
                delta["stop_reason"] = "end_turn"
                delta["stop_sequence"] = "final-sequence"
                delta["id"] = "msg_provider_overwrite"
                delta["content"] = [["type": "text", "text": "provider overwrite"]]
            }

            var usage: [String: Any] = [
                "input_tokens": NSNull(),
                "output_tokens": index,
                "provider_internal_\(index)": ["opaque": "usage-\(index)"],
            ]
            if index == fragmentCount - 1 {
                usage["cache_creation_input_tokens"] = 17
                usage["cache_read_input_tokens"] = 19
                usage["cache_creation"] = [
                    "ephemeral_1h_input_tokens": 23,
                    "ephemeral_5m_input_tokens": 29,
                ]
                usage["service_tier"] = "priority"
            }

            let maybeEvent = try accumulator.consume(
                providerFrame(
                    "message_delta",
                    ["type": "message_delta", "delta": delta, "usage": usage]
                )
            )
            let event = try #require(maybeEvent)
            switch event {
            // swiftlint:disable:next pattern_matching_keywords
            case .messageDelta(let deltaJSON, let usageJSON):
                let publishedUsage = try liveJSONObject(usageJSON)
                publishedOutputTokens.append(
                    try #require(publishedUsage["output_tokens"] as? Int)
                )
                finalPublishedDelta = try liveJSONObject(deltaJSON)
            default:
                Issue.record("Expected message_delta")
            }
        }
        _ = try accumulator.consume(
            providerFrame("message_stop", ["type": "message_stop"])
        )

        let turn = try accumulator.finish()
        #expect(publishedOutputTokens == Array(0..<fragmentCount))
        #expect(finalPublishedDelta["id"] as? String == "msg_provider_overwrite")
        #expect(turn.id == "msg_terminal_state")
        #expect(try jsonArray(turn.contentJSON).isEmpty)
        #expect(turn.stopReason == "end_turn")
        #expect(turn.stopSequenceJSON == Data(#""final-sequence""#.utf8))
        #expect(
            turn.usage
                == AnthropicUsage(
                    inputTokens: 11,
                    outputTokens: fragmentCount - 1,
                    cacheCreationInputTokens: 17,
                    cacheReadInputTokens: 19,
                    cacheCreationEphemeral1hInputTokens: 23,
                    cacheCreationEphemeral5mInputTokens: 29,
                    serviceTier: "priority"
                )
        )
    }

    @Test("Malformed supported terminal usage is rejected at the frame boundary")
    func malformedTerminalUsage() throws {
        let malformedUsage: [[String: Any]] = [
            ["cache_creation_input_tokens": -1],
            ["cache_read_input_tokens": "19"],
            ["cache_creation": []],
            ["cache_creation": ["ephemeral_1h_input_tokens": 23]],
            [
                "cache_creation": [
                    "ephemeral_1h_input_tokens": 23,
                    "ephemeral_5m_input_tokens": -1,
                ]
            ],
            ["service_tier": "internal"],
        ]

        for usage in malformedUsage {
            var accumulator = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 8_192)
            _ = try accumulator.consume(
                providerFrame(
                    "message_start",
                    [
                        "type": "message_start",
                        "message": providerMessage(id: "msg_invalid_usage"),
                    ]
                )
            )
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                _ = try accumulator.consume(
                    providerFrame(
                        "message_delta",
                        [
                            "type": "message_delta",
                            "delta": [
                                "stop_reason": "end_turn",
                                "stop_sequence": NSNull(),
                            ],
                            "usage": usage,
                        ]
                    )
                )
            }
        }

        let malformedDelta: [[String: Any]] = [
            ["stop_reason": 1],
            ["stop_sequence": []],
        ]
        for delta in malformedDelta {
            var accumulator = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 8_192)
            _ = try accumulator.consume(
                providerFrame(
                    "message_start",
                    [
                        "type": "message_start",
                        "message": providerMessage(id: "msg_invalid_delta"),
                    ]
                )
            )
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                _ = try accumulator.consume(
                    providerFrame(
                        "message_delta",
                        [
                            "type": "message_delta",
                            "delta": delta,
                            "usage": ["output_tokens": 1],
                        ]
                    )
                )
            }
        }
    }
}
