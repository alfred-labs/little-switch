import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic accumulator defensive coverage")
struct AnthropicAccumulatorCoverageTests {
    @Test("Citation deltas create the citation array when the block omitted it")
    func citationDeltaWithoutInitialArray() throws {
        var accumulator = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 8_192)
        let frames = try [
            providerFrame(
                "message_start",
                [
                    "type": "message_start",
                    "message": providerMessage(id: "msg_citation_fallback"),
                ]
            ),
            providerFrame(
                "content_block_start",
                [
                    "type": "content_block_start",
                    "index": 0,
                    "content_block": ["type": "text", "text": "answer"],
                ]
            ),
            providerFrame(
                "content_block_delta",
                [
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": [
                        "type": "citations_delta",
                        "citation": [
                            "type": "web_search_result_location",
                            "url": "https://swift.org/",
                        ],
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

        for frame in frames {
            _ = try accumulator.consume(frame)
        }

        let content = try jsonArray(accumulator.finish().contentJSON)
        let text = try jsonDictionary(try #require(content.first))
        let citations = try #require(text["citations"] as? [[String: Any]])
        #expect(citations.count == 1)
        #expect(citations[0]["url"] as? String == "https://swift.org/")
    }
}
