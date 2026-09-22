import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

extension AnthropicWebSearchTests {
    @Test("Non-streaming projection exposes server search blocks and the original model")
    func nonStreamingProjection() throws {
        let finalTurn = try makeAnthropicTurn(
            id: "msg_final",
            content: [
                ["type": "text", "text": "Current answer"]
            ],
            stopReason: "end_turn",
            inputTokens: 8,
            outputTokens: 5
        )
        let traces: [WebSearchTrace] = [
            WebSearchTrace(
                toolUseID: "srvtoolu_1",
                query: "Swift",
                content: .results([
                    WebSearchResult(
                        title: "Swift.org",
                        url: "https://swift.org/",
                        content: "ignored internally"
                    )
                ])
            ),
            WebSearchTrace(
                toolUseID: "srvtoolu_2",
                query: "Unavailable",
                content: .error("unavailable")
            ),
        ]

        let data = try AnthropicWebSearch.nonStreamingResponse(
            originalModel: "claude-opus-5",
            traces: traces,
            finalTurn: finalTurn,
            usage: AnthropicUsage(inputTokens: 21, outputTokens: 13)
        )
        let object = try anthropicWebSearchObject(data)
        #expect(object["id"] as? String == "msg_final")
        #expect(object["model"] as? String == "claude-opus-5")
        #expect(object["stop_reason"] as? String == "end_turn")
        let usage = try #require(object["usage"] as? [String: Any])
        #expect(usage["input_tokens"] as? Int == 21)
        #expect(usage["output_tokens"] as? Int == 13)
        #expect(
            usage["server_tool_use"] as? [String: Int]
                == ["web_search_requests": 1, "web_fetch_requests": 0]
        )
        let content = try #require(object["content"] as? [[String: Any]])
        #expect(
            content.map { $0["type"] as? String }
                == [
                    "server_tool_use",
                    "web_search_tool_result",
                    "server_tool_use",
                    "web_search_tool_result",
                    "text",
                ]
        )
        #expect(content[0]["id"] as? String == "srvtoolu_1")
        #expect(content[0]["name"] as? String == "web_search")
        #expect((content[0]["input"] as? [String: String]) == ["query": "Swift"])
        #expect((content[0]["caller"] as? [String: String]) == ["type": "direct"])
        #expect(content[1]["tool_use_id"] as? String == "srvtoolu_1")
        #expect((content[1]["caller"] as? [String: String]) == ["type": "direct"])
        let successfulResults = try #require(content[1]["content"] as? [[String: Any]])
        #expect(successfulResults.count == 1)
        #expect(successfulResults[0]["type"] as? String == "web_search_result")
        #expect(successfulResults[0]["url"] as? String == "https://swift.org/")
        #expect(successfulResults[0]["title"] as? String == "Swift.org")
        #expect((successfulResults[0]["encrypted_content"] as? String)?.isEmpty == false)
        #expect(successfulResults[0]["page_age"] is NSNull)
        #expect((content[3]["caller"] as? [String: String]) == ["type": "direct"])
        let error = try #require(content[3]["content"] as? [String: String])
        #expect(
            error == [
                "type": "web_search_tool_result_error",
                "error_code": "unavailable",
            ]
        )
    }

    @Test("No-search projection preserves final content while replacing the provider model")
    func noSearchProjection() throws {
        let finalTurn = try makeAnthropicTurn(
            id: "msg",
            content: [
                ["type": "tool_use", "id": "weather", "name": "weather", "input": [:]]
            ],
            stopReason: "tool_use",
            inputTokens: 2,
            outputTokens: 3
        )
        let projected = try AnthropicWebSearch.nonStreamingResponse(
            originalModel: "claude-sonnet-5",
            traces: [],
            finalTurn: finalTurn,
            usage: finalTurn.usage
        )
        let object = try anthropicWebSearchObject(projected)
        #expect(object["model"] as? String == "claude-sonnet-5")
        let content = try #require(object["content"] as? [[String: Any]])
        #expect(content.count == 1)
        #expect(content[0]["name"] as? String == "weather")
    }

    @Test("Projection never exposes the private search tool from a forced final turn")
    func privateToolDoesNotLeak() throws {
        let finalTurn = try makeAnthropicTurn(
            id: "msg",
            content: [
                ["type": "text", "text": "Search is unavailable."],
                [
                    "type": "tool_use",
                    "id": "search_again",
                    "name": "web_search",
                    "input": ["query": "retry"],
                ],
                ["type": "tool_use", "id": "weather", "name": "weather", "input": [:]],
            ],
            stopReason: "tool_use",
            inputTokens: 2,
            outputTokens: 3
        )

        let projected = try AnthropicWebSearch.nonStreamingResponse(
            originalModel: "claude-sonnet-5",
            traces: [],
            finalTurn: finalTurn,
            usage: finalTurn.usage
        )
        let object = try anthropicWebSearchObject(projected)
        let content = try #require(object["content"] as? [[String: Any]])

        #expect(content.map { $0["type"] as? String } == ["text", "tool_use"])
        #expect(content.last?["name"] as? String == "weather")
    }

    @Test("Projection rejects malformed fragments and preserves null terminal fields")
    func projectionValidation() throws {
        let nullTurn = bareAnthropicTurn(contentJSON: Data("[]".utf8))
        let nullProjection = try anthropicWebSearchObject(
            AnthropicWebSearch.nonStreamingResponse(
                originalModel: "claude",
                traces: [],
                finalTurn: nullTurn,
                usage: nullTurn.usage
            )
        )
        #expect(nullProjection["stop_reason"] is NSNull)
        #expect(nullProjection["stop_sequence"] is NSNull)

        for content in [Data("{}".utf8), Data("{".utf8)] {
            let malformed = bareAnthropicTurn(contentJSON: content)
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                try AnthropicWebSearch.nonStreamingResponse(
                    originalModel: "claude",
                    traces: [],
                    finalTurn: malformed,
                    usage: malformed.usage
                )
            }
        }

        let invalidStopSequence = bareAnthropicTurn(
            contentJSON: Data("[]".utf8),
            stopSequenceJSON: Data("{".utf8)
        )
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try AnthropicWebSearch.nonStreamingResponse(
                originalModel: "claude",
                traces: [],
                finalTurn: invalidStopSequence,
                usage: invalidStopSequence.usage
            )
        }
    }

    @Test("Delayed SSE emits complete indexed Anthropic events")
    func streamingProjection() throws {
        let finalTurn = try makeAnthropicTurn(
            id: "msg_final",
            content: [["type": "text", "text": "Current answer"]],
            stopReason: "end_turn",
            inputTokens: 8,
            outputTokens: 5
        )
        let trace = WebSearchTrace(
            toolUseID: "srvtoolu_1",
            query: "Swift",
            content: .results([
                WebSearchResult(
                    title: "Swift.org",
                    url: "https://swift.org/",
                    content: "snippet"
                )
            ])
        )

        let stream = try AnthropicWebSearch.streamingResponse(
            originalModel: "claude-opus-5",
            traces: [trace],
            finalTurn: finalTurn,
            usage: AnthropicUsage(inputTokens: 13, outputTokens: 9)
        )
        let events = try parseAnthropicEvents(stream)
        #expect(
            events.map(\.name) == [
                "message_start",
                "content_block_start",
                "content_block_delta",
                "content_block_stop",
                "content_block_start",
                "content_block_stop",
                "content_block_start",
                "content_block_delta",
                "content_block_stop",
                "message_delta",
                "message_stop",
            ]
        )
        let contentEvents = events.filter { $0.data["index"] != nil }
        #expect(
            contentEvents.compactMap { $0.data["index"] as? Int }
                == [0, 0, 0, 1, 1, 2, 2, 2]
        )
        let message = try #require(events[0].data["message"] as? [String: Any])
        #expect(message["model"] as? String == "claude-opus-5")
        let startUsage = try #require(message["usage"] as? [String: Any])
        #expect(startUsage["input_tokens"] as? Int == 13)
        #expect(startUsage["output_tokens"] as? Int == 0)
        #expect(
            startUsage["server_tool_use"] as? [String: Int]
                == ["web_search_requests": 0, "web_fetch_requests": 0]
        )
        let serverStart = try #require(events[1].data["content_block"] as? [String: Any])
        #expect((serverStart["input"] as? [String: Any])?.isEmpty == true)
        #expect((serverStart["caller"] as? [String: String]) == ["type": "direct"])
        let inputDelta = try #require(events[2].data["delta"] as? [String: String])
        #expect(inputDelta["type"] == "input_json_delta")
        #expect(inputDelta["partial_json"] == #"{"query":"Swift"}"#)
        let resultStart = try #require(events[4].data["content_block"] as? [String: Any])
        #expect((resultStart["caller"] as? [String: String]) == ["type": "direct"])
        let textStart = try #require(events[6].data["content_block"] as? [String: String])
        #expect(textStart == ["type": "text", "text": ""])
        let delta = try #require(events[7].data["delta"] as? [String: String])
        #expect(delta == ["type": "text_delta", "text": "Current answer"])
        let messageDelta = try #require(events[9].data["delta"] as? [String: Any])
        #expect(messageDelta["stop_reason"] as? String == "end_turn")
        let endUsage = try #require(events[9].data["usage"] as? [String: Any])
        #expect(endUsage["input_tokens"] as? Int == 13)
        #expect(endUsage["output_tokens"] as? Int == 9)
        #expect(
            endUsage["server_tool_use"] as? [String: Int]
                == ["web_search_requests": 1, "web_fetch_requests": 0]
        )
    }

    @Test("Streaming preserves unknown blocks and emits empty text deltas")
    func emptyAndUnknownStreamingContent() throws {
        let finalTurn = try makeAnthropicTurn(
            id: "msg_final",
            content: [
                ["type": "thinking", "thinking": "opaque"],
                ["type": "text", "text": ""],
            ],
            stopReason: nil,
            inputTokens: 1,
            outputTokens: 0
        )
        let stream = try AnthropicWebSearch.streamingResponse(
            originalModel: "claude",
            traces: [
                WebSearchTrace(
                    toolUseID: "srvtoolu_error",
                    query: "Swift",
                    content: .error("unavailable")
                )
            ],
            finalTurn: finalTurn,
            usage: finalTurn.usage
        )
        let events = try parseAnthropicEvents(stream)
        let starts = events.compactMap { $0.data["content_block"] as? [String: Any] }
        #expect(
            starts.map { $0["type"] as? String } == [
                "server_tool_use",
                "web_search_tool_result",
                "thinking",
                "text",
            ])
        let deltas = events.compactMap { $0.data["delta"] as? [String: Any] }
        #expect(
            deltas.contains {
                $0["type"] as? String == "text_delta"
                    && ($0["text"] as? String)?.isEmpty == true
            })
        let messageDelta = try #require(deltas.last)
        #expect(messageDelta["stop_reason"] is NSNull)
        #expect(messageDelta["stop_sequence"] is NSNull)
        let usage = try #require(
            events.last { $0.name == "message_delta" }?.data["usage"]
                as? [String: Any]
        )
        #expect(
            usage["server_tool_use"] as? [String: Int]
                == ["web_search_requests": 0, "web_fetch_requests": 0]
        )
    }

    @Test("Streaming rejects a text block without text")
    func invalidStreamingText() {
        let turn = bareAnthropicTurn(contentJSON: Data(#"[{"type":"text"}]"#.utf8))
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try AnthropicWebSearch.streamingResponse(
                originalModel: "claude",
                traces: [],
                finalTurn: turn,
                usage: turn.usage
            )
        }
    }

    @Test("Usage aggregation saturates instead of overflowing")
    func usageOverflow() {
        var usage = AnthropicUsage(inputTokens: Int.max - 1, outputTokens: Int.max)
        usage.add(AnthropicUsage(inputTokens: 2, outputTokens: 1))
        #expect(usage == AnthropicUsage(inputTokens: Int.max, outputTokens: Int.max))
    }

    @Test("Exact JSON encoding handles objects and fragments")
    func serializationForwarding() throws {
        let object: JSONObject = ["model": "claude", "stream": false]
        #expect(try AnthropicWebSearch.data(from: object) == Data(#"{"model":"claude","stream":false}"#.utf8))
        let fragment = try publicStreamFragment(Data(#""fragment""#.utf8))
        #expect(try publicStreamData(fragment) == Data(#""fragment""#.utf8))
    }

    @Test("Invalid JSON fragments become safe protocol errors")
    func serializationFailure() {
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try AnthropicWebSearch.fragmentObject(from: Data([0xFF]))
        }
    }

}

private func makeAnthropicTurn(
    id: String,
    content: [[String: Any]],
    stopReason: String?,
    inputTokens: Int,
    outputTokens: Int
) throws -> AnthropicModelTurn {
    AnthropicModelTurn(
        id: id,
        contentJSON: try JSONSerialization.data(
            withJSONObject: content,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ),
        stopReason: stopReason,
        stopSequenceJSON: Data("null".utf8),
        usage: AnthropicUsage(inputTokens: inputTokens, outputTokens: outputTokens),
        webSearchCall: nil
    )
}

private struct ParsedAnthropicEvent {
    let name: String
    let data: [String: Any]
}

private func parseAnthropicEvents(_ data: Data) throws -> [ParsedAnthropicEvent] {
    let text = try #require(String(data: data, encoding: .utf8))
    let chunks = text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
    return try chunks.map { chunk in
        let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false)
        let eventLine = try #require(lines.first)
        let dataLine = try #require(lines.dropFirst().first)
        #expect(eventLine.hasPrefix("event: "))
        #expect(dataLine.hasPrefix("data: "))
        let name = String(eventLine.dropFirst("event: ".count))
        let payload = Data(dataLine.dropFirst("data: ".count).utf8)
        let object = try #require(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )
        return ParsedAnthropicEvent(name: name, data: object)
    }
}
