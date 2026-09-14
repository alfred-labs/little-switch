import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic live web search streaming")
struct AnthropicWebSearchLiveStreamingTests {
    @Test("One search emits Claude-compatible native frames")
    func oneSearchPublicSession() throws {
        var session = AnthropicPublicStreamSession(originalModel: "claude-opus-5")
        var frames = try session.start(from: messageStartEvent(id: "msg_public", inputTokens: 12))
        frames += try feedPrivateSearchTurn(
            into: &session,
            providerToolID: "toolu_private",
            query: "latest Swift"
        )
        frames += try session.beginSearch(
            toolUseID: "srvtoolu_public_1",
            query: "latest Swift"
        )
        frames += try session.finishSearch(
            WebSearchTrace(
                toolUseID: "srvtoolu_public_1",
                query: "latest Swift",
                content: .results([
                    WebSearchResult(
                        title: "Swift.org",
                        url: "https://swift.org/",
                        content: "The Swift project"
                    )
                ])
            )
        )
        frames += try session.consumePublic(messageStartEvent(id: "msg_terminal", inputTokens: 4))
        frames += try session.consumePublic(
            contentStartEvent(index: 0, block: ["type": "text", "text": ""])
        )
        frames += try session.consumePublic(
            contentDeltaEvent(
                index: 0,
                delta: ["type": "text_delta", "text": "Current answer"]
            )
        )
        frames += try session.consumePublic(.contentStop(index: 0))
        frames += try closeProviderTurn(&session, stopReason: "end_turn", outputTokens: 9)
        frames += try session.finish(
            turn: terminalTurn(id: "msg_terminal", stopReason: "end_turn"),
            usage: AnthropicUsage(inputTokens: 16, outputTokens: 16)
        )
        try assertOneSearchPublicContract(frames)
    }

    @Test("Two searches use fresh IDs, contiguous indices, and cumulative usage")
    func twoSearchPublicSession() throws {
        var session = AnthropicPublicStreamSession(originalModel: "claude")
        var frames = try session.start(from: messageStartEvent(id: "msg_first", inputTokens: 1))
        for ordinal in 1...2 {
            let id = "srvtoolu_\(ordinal)"
            frames += try feedPrivateSearchTurn(
                into: &session,
                providerToolID: "toolu_private_\(ordinal)",
                query: "query \(ordinal)"
            )
            frames += try session.beginSearch(toolUseID: id, query: "query \(ordinal)")
            frames += try session.finishSearch(
                WebSearchTrace(
                    toolUseID: id,
                    query: "query \(ordinal)",
                    content: ordinal == 1
                        ? .results([
                            WebSearchResult(
                                title: "Result",
                                url: "https://example.com/\(ordinal)",
                                content: "snippet"
                            )
                        ])
                        : .error("invalid_request")
                )
            )
            if ordinal == 1 {
                frames += try session.consumePublic(
                    messageStartEvent(id: "msg_second", inputTokens: 2)
                )
            }
        }

        frames += try session.finish(
            turn: terminalTurn(id: "msg_first", stopReason: "pause_turn"),
            usage: AnthropicUsage(inputTokens: 8, outputTokens: 5)
        )
        let events = try parsePublicFrames(frames)
        let starts = events.compactMap { $0.payload["content_block"] as? [String: Any] }
        let serverIDs = starts.compactMap { block -> String? in
            guard block["type"] as? String == "server_tool_use" else { return nil }
            return block["id"] as? String
        }
        #expect(serverIDs == ["srvtoolu_1", "srvtoolu_2"])
        let resultIDs = starts.compactMap { block -> String? in
            guard block["type"] as? String == "web_search_tool_result" else { return nil }
            return block["tool_use_id"] as? String
        }
        #expect(resultIDs == serverIDs)
        let indices = events.compactMap { event -> Int? in
            guard event.name == "content_block_start" else { return nil }
            return event.payload["index"] as? Int
        }
        #expect(indices == [0, 1, 2, 3])

        let lastStart = try #require(starts.last)
        let errorResult = try #require(lastStart["content"] as? [String: Any])
        #expect(errorResult["type"] as? String == "web_search_tool_result_error")
        #expect(errorResult["error_code"] as? String == "invalid_tool_input")
        let messageDelta = try #require(events.last { $0.name == "message_delta" })
        let usage = try #require(messageDelta.payload["usage"] as? [String: Any])
        #expect(
            serverToolUsage(usage)
                == ["web_search_requests": 1, "web_fetch_requests": 0]
        )
        #expect(
            (messageDelta.payload["delta"] as? [String: Any])?["stop_reason"] as? String
                == "end_turn"
        )
    }

    @Test("Searched turns preserve public text but suppress every client tool")
    func searchedTurnMixedContent() throws {
        var session = AnthropicPublicStreamSession(originalModel: "claude")
        var frames = try session.start(from: messageStartEvent(id: "msg", inputTokens: 1))
        frames += try session.consumePublic(
            contentStartEvent(index: 0, block: ["type": "text", "text": ""])
        )
        frames += try session.consumePublic(
            contentDeltaEvent(
                index: 0,
                delta: ["type": "text_delta", "text": "I will check. "]
            )
        )
        frames += try session.consumePublic(.contentStop(index: 0))
        frames += try session.consumePublic(
            contentStartEvent(
                index: 1,
                block: [
                    "type": "tool_use",
                    "id": "toolu_weather",
                    "name": "weather",
                    "input": [:],
                ]
            )
        )
        frames += try session.consumePublic(
            contentDeltaEvent(
                index: 1,
                delta: [
                    "type": "input_json_delta",
                    "partial_json": #"{"city":"Paris"}"#,
                ]
            )
        )
        frames += try session.consumePublic(.contentStop(index: 1))
        frames += try session.consumePublic(
            contentStartEvent(
                index: 2,
                block: [
                    "type": "tool_use",
                    "id": "toolu_private",
                    "name": "web_search",
                    "input": [:],
                ]
            )
        )
        frames += try session.consumePublic(
            contentDeltaEvent(
                index: 2,
                delta: [
                    "type": "input_json_delta",
                    "partial_json": #"{"query":"Swift"}"#,
                ]
            )
        )
        frames += try session.consumePublic(.contentStop(index: 2))
        frames += try session.consumePublic(
            contentStartEvent(index: 3, block: ["type": "text", "text": ""])
        )
        frames += try session.consumePublic(
            contentDeltaEvent(
                index: 3,
                delta: ["type": "text_delta", "text": "Search requested."]
            )
        )
        frames += try session.consumePublic(.contentStop(index: 3))
        frames += try closeProviderTurn(&session, stopReason: "tool_use", outputTokens: 3)
        frames += try session.beginSearch(toolUseID: "srvtoolu_public", query: "Swift")
        frames += try session.finishSearch(
            WebSearchTrace(
                toolUseID: "srvtoolu_public",
                query: "Swift",
                content: .results([])
            )
        )
        let text = try utf8String(Data(frames.joined()))
        #expect(text.contains("I will check."))
        #expect(text.contains("Search requested."))
        #expect(!text.contains("toolu_weather"))
        #expect(!text.contains("toolu_private"))
        let starts = try parsePublicFrames(frames).compactMap {
            $0.payload["content_block"] as? [String: Any]
        }
        #expect(
            starts.map { $0["type"] as? String }
                == [
                    "text",
                    "server_tool_use",
                    "web_search_tool_result",
                    "text",
                ]
        )
        #expect(
            !starts.contains {
                $0["type"] as? String == "tool_use"
                    && $0["name"] as? String == "web_search"
            }
        )
    }

    @Test("A terminal ordinary client tool is flushed with public indices")
    func terminalOrdinaryTool() throws {
        var session = AnthropicPublicStreamSession(originalModel: "claude")
        var frames = try session.start(from: messageStartEvent(id: "msg", inputTokens: 1))
        frames += try session.consumePublic(
            contentStartEvent(
                index: 0,
                block: [
                    "type": "tool_use",
                    "id": "toolu_weather",
                    "name": "weather",
                    "input": [:],
                ]
            )
        )
        frames += try session.consumePublic(
            contentDeltaEvent(
                index: 0,
                delta: [
                    "type": "input_json_delta",
                    "partial_json": #"{"city":"Paris"}"#,
                ]
            )
        )
        frames += try session.consumePublic(.contentStop(index: 0))
        #expect(frames.count == 1)

        frames += try closeProviderTurn(&session, stopReason: "tool_use", outputTokens: 2)
        frames += try session.finish(
            turn: terminalTurn(id: "msg", stopReason: "tool_use"),
            usage: AnthropicUsage(inputTokens: 1, outputTokens: 2)
        )
        let events = try parsePublicFrames(frames)
        let starts = events.compactMap { $0.payload["content_block"] as? [String: Any] }
        let tool = try #require(starts.first { $0["type"] as? String == "tool_use" })
        #expect(tool["id"] as? String == "toolu_weather")
        #expect(tool["name"] as? String == "weather")
        #expect((tool["input"] as? [String: Any])?.isEmpty == true)
        let inputEvent = try #require(
            events.first {
                ($0.payload["delta"] as? [String: Any])?["type"] as? String
                    == "input_json_delta"
            }
        )
        let inputDelta = try #require(inputEvent.payload["delta"] as? [String: Any])
        #expect(inputDelta["partial_json"] as? String == #"{"city":"Paris"}"#)
        let toolEvents = events.filter { $0.payload["index"] as? Int == 0 }
        #expect(
            toolEvents.map(\.name)
                == ["content_block_start", "content_block_delta", "content_block_stop"]
        )
        #expect(events.filter { $0.name == "message_start" }.count == 1)
        #expect(events.filter { $0.name == "message_delta" }.count == 1)
        #expect(events.filter { $0.name == "message_stop" }.count == 1)
    }
}
