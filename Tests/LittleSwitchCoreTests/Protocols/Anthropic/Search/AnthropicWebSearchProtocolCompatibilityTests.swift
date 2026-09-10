import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic web search protocol compatibility")
struct AnthropicSearchProtocolTests {
    @Test("Every published web search tool version bridges as a direct call")
    func bridgedToolVersions() throws {
        let bridgedTools: [[String: Any]] = [
            ["type": "web_search_20250305"],
            ["type": "web_search_20260209"],
            ["type": "web_search_20260318", "response_inclusion": "excluded"],
            [
                "type": "web_search_20260209",
                "allowed_callers": ["code_execution_20260120"],
            ],
            [
                "type": "web_search_20260209",
                "allowed_callers": ["code_execution_20260120", "direct"],
            ],
        ]
        for tool in bridgedTools {
            let body = try JSONSerialization.data(
                withJSONObject: ["model": "claude", "messages": [], "tools": [tool]]
            )
            let candidate = try AnthropicWebSearch.prepare(
                body: body,
                targetModel: "provider-model",
                configuration: .firecrawlCloud
            )
            let prepared = try #require(candidate)
            let object = try anthropicWebSearchObject(prepared.upstreamBody)
            let upstreamTools = try #require(object["tools"] as? [[String: Any]])
            #expect(upstreamTools.map { $0["name"] as? String } == ["web_search"])
            #expect(upstreamTools.allSatisfy { $0["type"] == nil })
        }
    }

    @Test("A malformed caller list is still an invalid search request")
    func malformedCallerList() throws {
        let rejectedTools: [[String: Any]] = [
            ["type": "web_search_20260209", "allowed_callers": "direct"],
            ["type": "web_search_20260209", "allowed_callers": [42]],
        ]
        for tool in rejectedTools {
            let body = try JSONSerialization.data(
                withJSONObject: ["model": "claude", "messages": [], "tools": [tool]]
            )
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                try AnthropicWebSearch.prepare(
                    body: body,
                    targetModel: "provider-model",
                    configuration: .firecrawlCloud
                )
            }
        }
    }

    @Test("Terminal search errors remove impossible Anthropic tool choices")
    func terminalErrorToolChoice() throws {
        let turn = bareAnthropicTurn(
            contentJSON: Data(
                #"[{"type":"tool_use","id":"search_1","name":"web_search","input":{"query":"Swift"}}]"#
                    .utf8
            ),
            stopReason: "tool_use",
            webSearchCall: WebSearchToolCall(id: "search_1", query: "Swift")
        )
        let call = try #require(turn.webSearchCall)

        let forcedBase = Data(
            """
            {
              "messages": [],
              "tools": [
                {"name": "web_search", "input_schema": {"type": "object"}},
                {"name": "weather", "input_schema": {"type": "object"}}
              ],
              "tool_choice": {"type": "tool", "name": "web_search"}
            }
            """.utf8
        )
        let forced = try AnthropicWebSearch.followUpRequest(
            baseBody: forcedBase,
            turn: turn,
            toolCall: call,
            resultText: "unavailable",
            mode: .terminalError
        )
        let forcedObject = try anthropicWebSearchObject(forced)
        #expect(
            forcedObject["tool_choice"] as? [String: String]
                == ["type": "auto"]
        )
        #expect(
            (forcedObject["tools"] as? [[String: Any]])?.compactMap {
                $0["name"] as? String
            } == ["weather"]
        )

        let anyBase = Data(
            #"{"messages":[],"tools":[{"name":"web_search","input_schema":{"type":"object"}}],"tool_choice":{"type":"any"}}"#
                .utf8
        )
        let any = try AnthropicWebSearch.followUpRequest(
            baseBody: anyBase,
            turn: turn,
            toolCall: call,
            resultText: "unavailable",
            mode: .terminalError
        )
        let anyObject = try anthropicWebSearchObject(any)
        #expect(anyObject["tools"] == nil)
        #expect(anyObject["tool_choice"] == nil)
    }
}
