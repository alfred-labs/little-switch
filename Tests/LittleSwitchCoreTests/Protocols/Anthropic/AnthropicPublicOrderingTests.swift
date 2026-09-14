import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic public search ordering")
struct AnthropicPublicOrderingTests {
    @Test("Buffered JSON and SSE split searched-turn content around the native pair")
    func searchedTurnPublicContent() throws {
        let trace = WebSearchTrace(
            toolUseID: "srvtoolu_public",
            query: "Swift",
            content: .results([]),
            publicContentJSON: try jsonData([
                ["type": "text", "text": "I will search."],
                [
                    "type": "tool_use",
                    "id": "toolu_weather",
                    "name": "weather",
                    "input": ["city": "Paris"],
                ],
                ["type": "thinking", "thinking": "Check current sources."],
                [
                    "type": "tool_use",
                    "id": "toolu_private",
                    "name": "web_search",
                    "input": ["query": "Swift"],
                ],
                ["type": "text", "text": "Search completed."],
            ])
        )
        let finalTurn = AnthropicModelTurn(
            id: "msg_final",
            contentJSON: try jsonData([["type": "text", "text": "Final answer"]]),
            stopReason: "pause_turn",
            stopSequenceJSON: Data("null".utf8),
            usage: AnthropicUsage(inputTokens: 1, outputTokens: 1),
            webSearchCall: nil
        )

        let response = try liveJSONObject(
            AnthropicWebSearch.nonStreamingResponse(
                originalModel: "claude",
                traces: [trace],
                finalTurn: finalTurn,
                usage: AnthropicUsage(inputTokens: 3, outputTokens: 2)
            )
        )
        let content = try #require(response["content"] as? [[String: Any]])
        let types = content.map { $0["type"] as? String }
        #expect(
            types
                == [
                    "text",
                    "thinking",
                    "server_tool_use",
                    "web_search_tool_result",
                    "text",
                    "text",
                ]
        )
        #expect(content[0]["text"] as? String == "I will search.")
        #expect(content[1]["thinking"] as? String == "Check current sources.")
        #expect(content[4]["text"] as? String == "Search completed.")
        #expect(content[5]["text"] as? String == "Final answer")
        #expect(response["stop_reason"] as? String == "end_turn")
        let responseText = try utf8String(jsonData(response))
        #expect(!responseText.contains("toolu_weather"))
        #expect(!responseText.contains("toolu_private"))

        let stream = try AnthropicWebSearch.streamingResponse(
            originalModel: "claude",
            traces: [trace],
            finalTurn: finalTurn,
            usage: AnthropicUsage(inputTokens: 3, outputTokens: 2)
        )
        let streamTypes = try publicOrderingEvents(stream).compactMap {
            ($0.payload["content_block"] as? [String: Any])?["type"] as? String
        }
        #expect(streamTypes == types)
    }
}

private func publicOrderingEvents(_ stream: Data) throws -> [PublicAnthropicEvent] {
    let text = try utf8String(stream)
    let frames = text.components(separatedBy: "\n\n")
        .filter { !$0.isEmpty }
        .map { Data(($0 + "\n\n").utf8) }
    return try parsePublicFrames(frames)
}
