import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

extension AnthropicWebSearchOwnershipTests {
    @Test("The parser finds only the private tool bound to this request")
    func parsedToolOwnership() throws {
        let body = try ownershipProviderResponse()
        let turn = try AnthropicWebSearch.parseModelTurn(body, privateToolName: "__little_switch_web_search")
        #expect(turn.webSearchCall == WebSearchToolCall(id: "private_search", query: "Swift"))
        #expect(try AnthropicWebSearch.parseModelTurn(body, privateToolName: nil).webSearchCall == nil)
    }

    @Test("Buffered projections retain the client search tool and search-relative text order")
    func bufferedProjectionOwnership() throws {
        let trace = WebSearchTrace(
            toolUseID: "srvtoolu_1",
            query: "Swift",
            content: .results([]),
            publicContentJSON: try jsonData([
                ["type": "text", "text": "Before"],
                [
                    "type": "tool_use", "id": "private_search", "name": "__little_switch_web_search",
                    "input": ["query": "Swift"],
                ],
                ["type": "text", "text": "After"],
            ])
        )
        let final = bareAnthropicTurn(contentJSON: try jsonData([ownershipClientCall()]), stopReason: "tool_use")
        let body = try AnthropicWebSearch.nonStreamingResponse(
            originalModel: "claude",
            traces: [trace],
            finalTurn: final,
            usage: final.usage,
            privateToolName: "__little_switch_web_search"
        )
        let content = try #require(anthropicWebSearchObject(body)["content"] as? [[String: Any]])
        #expect(
            content.compactMap { $0["type"] as? String } == [
                "text", "server_tool_use", "web_search_tool_result", "text", "tool_use",
            ])
        #expect(content.first?["text"] as? String == "Before")
        #expect(content.dropFirst(3).first?["text"] as? String == "After")
        #expect(NSDictionary(dictionary: try #require(content.last)).isEqual(to: ownershipClientCall()))
        let stream = try AnthropicWebSearch.streamingResponse(
            originalModel: "claude",
            traces: [trace],
            finalTurn: final,
            usage: final.usage,
            privateToolName: "__little_switch_web_search"
        )
        let starts = try ownershipStreamStarts(stream)
        #expect(starts.compactMap { $0["type"] as? String } == content.compactMap { $0["type"] as? String })
        #expect(starts.last?["name"] as? String == "web_search")
    }

    @Test("A projection without a private binding retains all ordinary search-named tools")
    func unownedProjection() throws {
        let turn = try AnthropicWebSearch.parseModelTurn(ownershipProviderResponse(), privateToolName: nil)
        let content = try AnthropicWebSearch.responseContent(traces: [], finalTurn: turn, privateToolName: nil)
        #expect(content.compactMap { $0["name"]?.string } == ["web_search", "__little_switch_web_search"])
    }

    @Test("Search follow-ups retain only the actual bound call and remove only its declaration on error")
    func followUpOwnership() throws {
        let body = try ownershipSearchBody(
            tools: [ownershipClientTool("web_search"), ownershipClientTool("__little_switch_web_search")],
            choice: ["type": "tool", "name": "__little_switch_web_search"]
        )
        let turn = try AnthropicWebSearch.parseModelTurn(ownershipProviderResponse())
        let followUp = try AnthropicWebSearch.followUpRequest(
            baseBody: body,
            turn: turn,
            toolCall: WebSearchToolCall(id: "private_search", query: "Swift"),
            resultText: "Unavailable",
            mode: .terminalError,
            privateToolName: "__little_switch_web_search"
        )
        let object = try anthropicWebSearchObject(followUp)
        #expect((object["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } == ["web_search"])
        #expect(object["tool_choice"] as? [String: String] == ["type": "auto"])
        let messages = try #require(object["messages"] as? [[String: Any]])
        #expect(
            (messages.first?["content"] as? [[String: Any]])?.compactMap { $0["id"] as? String } == ["private_search"])
        #expect((messages.last?["content"] as? [[String: Any]])?.first?["is_error"] as? Bool == true)
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try AnthropicWebSearch.followUpRequest(
                baseBody: body,
                turn: turn,
                toolCall: WebSearchToolCall(id: "client_search", query: "client"),
                resultText: "Unavailable",
                mode: .result,
                privateToolName: nil
            )
        }
    }

    @Test("Live streams publish same-name client tools when no private search was requested")
    func streamedClientTool() throws {
        for binding: String? in [nil, "__little_switch_web_search"] {
            var session = AnthropicPublicStreamSession(originalModel: "claude", privateToolName: binding)
            var frames = try session.start(from: messageStartEvent(id: "msg", inputTokens: 1))
            frames += try feedPrivateSearchTurn(into: &session, providerToolID: "client_search", query: "client")
            frames += try session.finish(
                turn: terminalTurn(id: "msg", stopReason: "tool_use"), usage: .init(inputTokens: 1, outputTokens: 1))
            let events = try parsePublicFrames(frames)
            let tools = events.compactMap { $0.payload["content_block"] as? [String: Any] }
            #expect(tools.compactMap { $0["name"] as? String } == ["web_search"])
        }
    }

    @Test("Fragmented provider tool arguments retain the request's private binding in the accumulator")
    func accumulatedToolOwnership() throws {
        for binding: String? in [nil, "__little_switch_web_search"] {
            var accumulator = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 16 * 1_024, privateToolName: binding)
            for frame in try ownershipProviderFrames() {
                try accumulator.consume(frame)
            }
            let turn = try accumulator.finish()
            let expected = binding == nil ? nil : WebSearchToolCall(id: "private_search", query: "Swift")
            #expect(turn.webSearchCall == expected)
        }
    }
}

func ownershipClientCall() -> [String: Any] {
    ["type": "tool_use", "id": "client_search", "name": "web_search", "input": ["query": "client"]]
}

func ownershipProviderResponse() throws -> Data {
    try jsonData([
        "id": "msg", "stop_reason": "tool_use", "usage": ["input_tokens": 1, "output_tokens": 1],
        "content": [
            ownershipClientCall(),
            [
                "type": "tool_use", "id": "private_search", "name": "__little_switch_web_search",
                "input": ["query": "Swift"],
            ],
        ],
    ])
}

func ownershipStreamStarts(_ stream: Data) throws -> [[String: Any]] {
    let frames = try utf8String(stream).components(separatedBy: "\n\n").filter { !$0.isEmpty }.map {
        Data(($0 + "\n\n").utf8)
    }
    return try parsePublicFrames(frames).compactMap { $0.payload["content_block"] as? [String: Any] }
}

func ownershipProviderFrames() throws -> [ServerSentEventFrame] {
    var frames = try [providerFrame("message_start", ["type": "message_start", "message": providerMessage(id: "msg")])]
    for (index, name) in ["web_search", "__little_switch_web_search"].enumerated() {
        let id = index == 0 ? "client_search" : "private_search"
        frames.append(
            try providerFrame(
                "content_block_start",
                [
                    "type": "content_block_start", "index": index,
                    "content_block": ["type": "tool_use", "id": id, "name": name, "input": [:]],
                ]))
        for fragment in ["{\"query\":", "\"Swift\"}"] {
            frames.append(
                try providerFrame(
                    "content_block_delta",
                    [
                        "type": "content_block_delta", "index": index,
                        "delta": ["type": "input_json_delta", "partial_json": fragment],
                    ]))
        }
        frames.append(try providerFrame("content_block_stop", ["type": "content_block_stop", "index": index]))
    }
    frames.append(
        try providerFrame(
            "message_delta",
            [
                "type": "message_delta", "delta": ["stop_reason": "tool_use"], "usage": ["output_tokens": 1],
            ]))
    frames.append(try providerFrame("message_stop", ["type": "message_stop"]))
    return frames
}
