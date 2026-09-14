import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic public stream terminal behavior")
struct AnthropicPublicStreamTerminalTests {
    @Test("Fatal public errors are safe and terminal")
    func fatalPublicError() throws {
        var session = AnthropicPublicStreamSession(originalModel: "claude")
        var frames = try session.start(from: messageStartEvent(id: "msg", inputTokens: 1))
        frames += try session.fail(message: "provider body with secret token")

        let events = try parsePublicFrames(frames)
        #expect(events.map(\.name) == ["message_start", "error"])
        let lastEvent = try #require(events.last)
        let error = try #require(lastEvent.payload["error"] as? [String: Any])
        #expect(error["type"] as? String == "api_error")
        #expect(error["message"] as? String == "Internal server error")
        #expect(!(try utf8String(Data(frames.joined()))).contains("secret token"))
        #expect(events.allSatisfy { $0.name != "message_stop" })

        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try session.finish(
                turn: terminalTurn(id: "msg", stopReason: "end_turn"),
                usage: AnthropicUsage(inputTokens: 1, outputTokens: 1)
            )
        }
    }

    @Test("Fatal public errors may terminate before message start")
    func fatalPublicErrorBeforeStart() throws {
        var session = AnthropicPublicStreamSession(originalModel: "claude")
        let frames = try session.fail(message: "provider secret")

        let events = try parsePublicFrames(frames)
        #expect(events.map(\.name) == ["error"])
        #expect(events.allSatisfy { $0.name != "message_stop" })
        #expect(!(try utf8String(Data(frames.joined()))).contains("provider secret"))

        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try session.fail(message: "second terminal")
        }
    }

    @Test("Multiple internal message deltas produce one public terminal delta")
    func multipleInternalMessageDeltas() throws {
        var session = AnthropicPublicStreamSession(originalModel: "claude")
        var frames = try session.start(from: messageStartEvent(id: "msg", inputTokens: 2))
        frames += try session.consumePublic(
            .messageDelta(
                deltaJSON: try jsonData([
                    "stop_reason": NSNull(),
                    "stop_sequence": "provider-sequence",
                ]),
                usageJSON: try jsonData(["output_tokens": 2])
            )
        )
        frames += try session.consumePublic(
            .messageDelta(
                deltaJSON: try jsonData([
                    "stop_reason": "end_turn",
                    "stop_sequence": NSNull(),
                ]),
                usageJSON: try jsonData(["output_tokens": 4])
            )
        )
        frames += try session.consumePublic(.messageStop)
        frames += try session.finish(
            turn: terminalTurn(id: "msg", stopReason: "end_turn"),
            usage: AnthropicUsage(
                inputTokens: 2,
                outputTokens: 4,
                cacheCreationInputTokens: 5,
                cacheReadInputTokens: 6,
                cacheCreationEphemeral1hInputTokens: 3,
                cacheCreationEphemeral5mInputTokens: 2,
                serviceTier: "priority"
            )
        )

        let events = try parsePublicFrames(frames)
        #expect(events.filter { $0.name == "message_delta" }.count == 1)
        #expect(events.filter { $0.name == "message_stop" }.count == 1)
        let terminalUsage = try #require(
            events.last { $0.name == "message_delta" }?.payload["usage"]
                as? [String: Any]
        )
        #expect(
            NSDictionary(dictionary: terminalUsage).isEqual(to: [
                "input_tokens": 2,
                "output_tokens": 4,
                "cache_creation_input_tokens": 5,
                "cache_read_input_tokens": 6,
                "cache_creation": [
                    "ephemeral_1h_input_tokens": 3,
                    "ephemeral_5m_input_tokens": 2,
                ],
                "service_tier": "priority",
                "server_tool_use": [
                    "web_search_requests": 0,
                    "web_fetch_requests": 0,
                ],
            ])
        )
    }

    @Test("Search failures use only native public error codes")
    func nativeSearchErrorCodes() throws {
        let cases = [
            ("invalid_request", "invalid_tool_input"),
            ("invalid_tool_input", "invalid_tool_input"),
            ("unavailable", "unavailable"),
            ("max_uses_exceeded", "max_uses_exceeded"),
            ("too_many_requests", "too_many_requests"),
            ("query_too_long", "query_too_long"),
            ("request_too_large", "request_too_large"),
            ("private_provider_failure", "unavailable"),
        ]
        for (input, expected) in cases {
            var session = AnthropicPublicStreamSession(originalModel: "claude")
            _ = try session.start(from: messageStartEvent(id: "msg", inputTokens: 1))
            _ = try closeProviderTurn(&session, stopReason: "tool_use", outputTokens: 1)
            _ = try session.beginSearch(toolUseID: "srvtoolu_error", query: "query")
            let frames = try session.finishSearch(
                WebSearchTrace(
                    toolUseID: "srvtoolu_error",
                    query: "query",
                    content: .error(input)
                )
            )
            let events = try parsePublicFrames(frames)
            let start = try #require(events.first)
            let block = try #require(start.payload["content_block"] as? [String: Any])
            let error = try #require(block["content"] as? [String: Any])
            #expect(error["error_code"] as? String == expected)
        }
    }
}
