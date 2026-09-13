import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic defensive protocol coverage")
struct AnthropicDefensiveCoverageTests {
    @Test("Public encoding accepts nullable values and rejects malformed JSON")
    func publicEncodingValidation() throws {
        #expect(try publicTokenCount(nil) == 0)
        #expect(try publicTokenCount(.null) == 0)
        for value: JSONValue in [-1, "one"] {
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                _ = try publicTokenCount(value)
            }
        }

        #expect(try publicStreamFragment(nil) == .null)
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try publicStreamFragment(Data("{".utf8))
        }
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try publicStreamObject(Data("[]".utf8))
        }
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try publicStreamObject(Data("{".utf8))
        }
    }

    @Test("Anthropic JSON boundary rejects values outside the JSON grammar")
    func nonJSONEncodingValues() {
        for json in [#"{"invalid":NaN}"#, #"{"invalid":undefined}"#] {
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                _ = try AnthropicWebSearch.object(from: Data(json.utf8))
            }
        }
    }

    @Test("Empty optional search locations are rejected")
    func emptySearchLocation() {
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try AnthropicWebSearch.searchOptions(
                from: [
                    "user_location": [
                        "type": "approximate",
                        "city": " \n\t ",
                    ]
                ]
            )
        }
    }

    @Test("Provider accumulator rejects malformed lifecycle branches")
    func accumulatorLifecycleValidation() throws {
        var providerError = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 4_096)
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try providerError.consume(
                providerFrame("error", ["type": "error"])
            )
        }

        var malformedStart = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 4_096)
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try malformedStart.consume(
                providerFrame(
                    "message_start",
                    [
                        "type": "message_start",
                        "message": providerMessage(id: ""),
                    ]
                )
            )
        }

        var invalidBlockIndex = try startedAccumulator()
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try invalidBlockIndex.consume(
                providerFrame(
                    "content_block_start",
                    [
                        "type": "content_block_start",
                        "index": -1,
                        "content_block": ["type": "text", "text": ""],
                    ]
                )
            )
        }

        var invalidStop = try startedAccumulator()
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try invalidStop.consume(
                providerFrame(
                    "content_block_stop",
                    ["type": "content_block_stop", "index": 0]
                )
            )
        }

        var invalidMessageDelta = try startedAccumulator()
        _ = try invalidMessageDelta.consume(
            try blockStartFrame(index: 0, block: ["type": "text", "text": ""])
        )
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try invalidMessageDelta.consume(try terminalDeltaFrame())
        }

        var invalidMessageStop = try startedAccumulator()
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try invalidMessageStop.consume(
                providerFrame("message_stop", ["type": "message_stop"])
            )
        }

        var nonObject = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 4_096)
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try nonObject.consume(
                ServerSentEventFrame(
                    event: "ping",
                    data: Data("[]".utf8),
                    terminal: false
                )
            )
        }
    }

    @Test("Provider accumulator validates every supported block shape")
    func accumulatorBlockValidation() throws {
        let malformedBlocks: [[String: Any]] = [
            ["type": "text"],
            ["type": "text", "text": "", "citations": [:]],
            ["type": "thinking"],
            ["type": "thinking", "thinking": "", "signature": 42],
            [
                "type": "tool_use",
                "id": "toolu_invalid",
                "name": "weather",
                "input": ["city": "Paris"],
            ],
        ]
        for block in malformedBlocks {
            var accumulator = try startedAccumulator()
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                _ = try accumulator.consume(try blockStartFrame(index: 0, block: block))
            }
        }

        let invalidDeltas: [([String: Any], [String: Any])] = [
            (
                ["type": "text", "text": ""],
                ["type": "text_delta"]
            ),
            (
                ["type": "text", "text": ""],
                ["type": "input_json_delta", "partial_json": "{}"]
            ),
            (
                ["type": "thinking", "thinking": ""],
                ["type": "signature_delta"]
            ),
            (
                ["type": "text", "text": ""],
                ["type": "citations_delta", "citation": [:]]
            ),
        ]
        for (block, delta) in invalidDeltas {
            var accumulator = try startedAccumulator()
            _ = try accumulator.consume(try blockStartFrame(index: 0, block: block))
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                _ = try accumulator.consume(try blockDeltaFrame(index: 0, delta: delta))
            }
        }
    }

    @Test("Provider accumulator completes empty tools and unknown blocks")
    func accumulatorEmptyAndUnknownBlocks() throws {
        var emptyTool = try startedAccumulator(id: "msg_empty_tool")
        _ = try emptyTool.consume(
            try blockStartFrame(
                index: 0,
                block: [
                    "type": "tool_use",
                    "id": "toolu_empty",
                    "name": "weather",
                    "input": [:],
                ]
            )
        )
        _ = try emptyTool.consume(try blockStopFrame(index: 0))
        _ = try emptyTool.consume(try terminalDeltaFrame())
        _ = try emptyTool.consume(try messageStopFrame())
        let toolContent = try jsonArray(emptyTool.finish().contentJSON)
        let tool = try jsonDictionary(try #require(toolContent.first))
        #expect((tool["input"] as? [String: Any])?.isEmpty == true)

        var unknown = try startedAccumulator(id: "msg_unknown_block")
        _ = try unknown.consume(
            try blockStartFrame(
                index: 0,
                block: ["type": "provider_future_block", "opaque": true]
            )
        )
        _ = try unknown.consume(try blockStopFrame(index: 0))
        _ = try unknown.consume(try terminalDeltaFrame())
        _ = try unknown.consume(try messageStopFrame())
        let unknownContent = try jsonArray(unknown.finish().contentJSON)
        let unknownBlock = try jsonDictionary(try #require(unknownContent.first))
        #expect(unknownBlock["type"] as? String == "provider_future_block")
        #expect(unknownBlock["opaque"] as? Bool == true)
    }
}

extension AnthropicDefensiveCoverageTests {
    @Test("Public session rejects invalid state and provider events")
    func publicSessionLifecycleValidation() throws {
        var emptyModel = AnthropicPublicStreamSession(originalModel: "")
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try emptyModel.start(from: messageStartEvent(id: "msg", inputTokens: 0))
        }

        var malformedMessage = AnthropicPublicStreamSession(originalModel: "claude")
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try malformedMessage.start(
                from: .messageStart(messageJSON: try jsonData(["id": "msg"]))
            )
        }

        var unstarted = AnthropicPublicStreamSession(originalModel: "claude")
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try unstarted.consumePublic(.ping)
        }
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try unstarted.beginSearch(toolUseID: "srvtoolu", query: "Swift")
        }

        var repeatedStart = try startedCoveragePublicSession()
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try repeatedStart.consumePublic(
                messageStartEvent(id: "msg_second", inputTokens: 0)
            )
        }

        var activeBlock = try startedCoveragePublicSession()
        _ = try activeBlock.consumePublic(
            contentStartEvent(index: 0, block: ["type": "text", "text": ""])
        )
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try activeBlock.consumePublic(
                .messageDelta(
                    deltaJSON: try jsonData(["stop_reason": "end_turn"]),
                    usageJSON: try jsonData(["output_tokens": 1])
                )
            )
        }

        var missingDelta = try startedCoveragePublicSession()
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try missingDelta.consumePublic(.messageStop)
        }

        var invalidStart = try startedCoveragePublicSession()
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try invalidStart.consumePublic(
                contentStartEvent(index: -1, block: ["type": "text", "text": ""])
            )
        }

        var missingType = try startedCoveragePublicSession()
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try missingType.consumePublic(contentStartEvent(index: 0, block: [:]))
        }

        var unknownDelta = try startedCoveragePublicSession()
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try unknownDelta.consumePublic(
                contentDeltaEvent(
                    index: 0,
                    delta: ["type": "text_delta", "text": "orphan"]
                )
            )
        }

        var unknownStop = try startedCoveragePublicSession()
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try unknownStop.consumePublic(.contentStop(index: 0))
        }
    }

    @Test("Buffered provider replay rejects incomplete internal state")
    func bufferedReplayValidation() throws {
        let malformedBuffers: [[AnthropicProviderStreamEvent]] = [
            [
                .contentStart(
                    index: 0,
                    blockJSON: try jsonData(["text": "missing type"])
                )
            ],
            [
                .contentDelta(
                    index: 0,
                    deltaJSON: try jsonData(["type": "text_delta", "text": "orphan"])
                )
            ],
            [.contentStop(index: 0)],
            [.ping],
            [
                .contentStart(
                    index: 0,
                    blockJSON: try jsonData(["type": "provider_future_block"])
                )
            ],
            [
                .contentStart(
                    index: 0,
                    blockJSON: try jsonData(["type": "text"])
                ),
                .contentStop(index: 0),
            ],
            [
                .contentStart(
                    index: 0,
                    blockJSON: try jsonData(["type": "thinking"])
                ),
                .contentStop(index: 0),
            ],
        ]

        for bufferedEvents in malformedBuffers {
            var session = try startedCoveragePublicSession()
            session.bufferedEvents = bufferedEvents
            _ = try session.consumePublic(
                .messageDelta(
                    deltaJSON: try jsonData(["stop_reason": "end_turn"]),
                    usageJSON: try jsonData(["output_tokens": 1])
                )
            )
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                _ = try session.consumePublic(.messageStop)
            }
        }
    }

    @Test("Initial thinking content becomes public synthetic deltas")
    func initialThinkingSyntheticDeltas() throws {
        var session = try startedCoveragePublicSession()
        let frames = try session.consumePublic(
            contentStartEvent(
                index: 0,
                block: [
                    "type": "thinking",
                    "thinking": "reasoning",
                    "signature": "opaque-signature",
                ]
            )
        )
        let events = try parsePublicFrames(frames)
        let deltas = events.compactMap { $0.payload["delta"] as? [String: Any] }
        #expect(deltas.map { $0["type"] as? String } == ["thinking_delta", "signature_delta"])
    }

    @Test("Projection rejects malformed trace and streaming blocks")
    func projectionValidation() throws {
        let finalTurn = bareAnthropicTurn(contentJSON: Data("[]".utf8))
        for publicContent in [Data("{}".utf8), Data("{".utf8)] {
            let trace = WebSearchTrace(
                toolUseID: "srvtoolu",
                query: "Swift",
                content: .results([]),
                publicContentJSON: publicContent
            )
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                _ = try AnthropicWebSearch.responseContent(
                    traces: [trace],
                    finalTurn: finalTurn
                )
            }
        }

        let malformedBlocks: [[String: Any]] = [
            ["type": "server_tool_use", "id": "srvtoolu", "name": "web_search"],
            ["type": "tool_use", "id": "toolu", "name": "weather"],
            ["type": "thinking"],
        ]
        for block in malformedBlocks {
            let turn = bareAnthropicTurn(contentJSON: try jsonData([block]))
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                _ = try AnthropicWebSearch.streamingResponse(
                    originalModel: "claude",
                    traces: [],
                    finalTurn: turn,
                    usage: turn.usage
                )
            }
        }

        let thinkingTurn = bareAnthropicTurn(
            contentJSON: try jsonData([
                [
                    "type": "thinking",
                    "thinking": "reasoning",
                    "signature": "opaque-signature",
                ],
                [
                    "type": "tool_use",
                    "id": "toolu_weather",
                    "name": "weather",
                    "input": ["city": "Paris"],
                ],
            ])
        )
        let stream = try AnthropicWebSearch.streamingResponse(
            originalModel: "claude",
            traces: [],
            finalTurn: thinkingTurn,
            usage: thinkingTurn.usage
        )
        let streamText = try utf8String(stream)
        #expect(streamText.contains("thinking_delta"))
        #expect(streamText.contains("signature_delta"))
    }
}

private func startedAccumulator(
    id: String = "msg_coverage"
) throws -> AnthropicStreamingTurnAccumulator {
    var accumulator = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 64 * 1_024)
    _ = try accumulator.consume(
        providerFrame(
            "message_start",
            [
                "type": "message_start",
                "message": providerMessage(id: id),
            ]
        )
    )
    return accumulator
}

private func blockStartFrame(
    index: Int,
    block: [String: Any]
) throws -> ServerSentEventFrame {
    try providerFrame(
        "content_block_start",
        [
            "type": "content_block_start",
            "index": index,
            "content_block": block,
        ]
    )
}

private func blockDeltaFrame(
    index: Int,
    delta: [String: Any]
) throws -> ServerSentEventFrame {
    try providerFrame(
        "content_block_delta",
        [
            "type": "content_block_delta",
            "index": index,
            "delta": delta,
        ]
    )
}

private func blockStopFrame(index: Int) throws -> ServerSentEventFrame {
    try providerFrame(
        "content_block_stop",
        ["type": "content_block_stop", "index": index]
    )
}

private func terminalDeltaFrame() throws -> ServerSentEventFrame {
    try providerFrame(
        "message_delta",
        [
            "type": "message_delta",
            "delta": ["stop_reason": "end_turn", "stop_sequence": NSNull()],
            "usage": ["output_tokens": 1],
        ]
    )
}

private func messageStopFrame() throws -> ServerSentEventFrame {
    try providerFrame("message_stop", ["type": "message_stop"])
}
