import Foundation
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic web search bridge")
struct AnthropicWebSearchTests {
    @Test("Disabled built-in search is removed while ordinary tools keep transparent proxying")
    func ineligibleRequests() throws {
        let searchBody = Data(
            #"{"model":"claude","messages":[],"tools":[{"type":"web_search_20250305","max_uses":2}]}"#.utf8
        )
        let disabled = try AnthropicWebSearch.prepare(
            body: searchBody,
            targetModel: "provider-model",
            configuration: .disabled
        )
        #expect(disabled?.maximumUses == 0)
        #expect(disabled?.privateToolName == nil)

        let ordinaryBody = Data(
            #"{"model":"claude","messages":[],"tools":[{"name":"weather","input_schema":{"type":"object"}}]}"#.utf8
        )
        #expect(
            try AnthropicWebSearch.prepare(
                body: ordinaryBody,
                targetModel: "provider-model",
                configuration: .firecrawlCloud
            ) == nil
        )
    }

    @Test("Built-in search becomes one private tool without losing opaque fields")
    func preparesPrivateTool() throws {
        let body = Data(
            """
            {
              "model": "claude-opus-5",
              "stream": true,
              "metadata": {"user_id": "opaque"},
              "messages": [{"role": "user", "content": "latest Swift"}],
              "tools": [
                {"type": "web_search_20250305", "name": "ignored", "max_uses": 2},
                {"name": "web_search", "description": "collision", "input_schema": {"type": "object"}},
                {"name": "weather", "description": "Weather", "input_schema": {"type": "object"}}
              ],
              "unknown": [1, 2, 3]
            }
            """.utf8
        )

        let candidate = try AnthropicWebSearch.prepare(
            body: body,
            targetModel: "glm-5",
            configuration: WebSearchConfiguration(maximumUses: 3)
        )
        let prepared = try #require(candidate)
        #expect(prepared.originalModel == "claude-opus-5")
        #expect(prepared.streaming)
        #expect(prepared.maximumUses == 2)

        let object = try anthropicWebSearchObject(prepared.upstreamBody)
        #expect(object["model"] as? String == "glm-5")
        #expect(object["stream"] as? Bool == true)
        #expect(object["metadata"] as? [String: String] == ["user_id": "opaque"])
        #expect(object["unknown"] as? [Int] == [1, 2, 3])
        #expect((object["messages"] as? [[String: Any]])?.count == 1)

        let tools = try #require(object["tools"] as? [[String: Any]])
        #expect(tools.count == 3)
        let search = try #require(tools.first)
        #expect(search["name"] as? String == "__little_switch_web_search")
        #expect(tools[1]["name"] as? String == "web_search")
        #expect(
            search["description"] as? String
                == "Search the web for current information. Use this to find up-to-date information about any topic."
        )
        let schema = try #require(search["input_schema"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        #expect(schema["required"] as? [String] == ["query"])
        let properties = try #require(schema["properties"] as? [String: Any])
        let query = try #require(properties["query"] as? [String: String])
        #expect(
            query == [
                "type": "string",
                "description": "The search query to look up on the web",
            ]
        )
        #expect(tools.last?["name"] as? String == "weather")
    }

    @Test("Search policy maps allowed domains and approximate user location")
    func searchPolicyOptions() throws {
        let body = Data(
            """
            {
              "model": "claude",
              "stream": true,
              "messages": [],
              "tools": [{
                "type": "web_search_20250305",
                "allowed_domains": [" swift.org ", "github.com"],
                "user_location": {
                  "type": "approximate",
                  "city": "Paris",
                  "region": "Ile-de-France",
                  "country": "FR",
                  "timezone": "Europe/Paris"
                }
              }]
            }
            """.utf8
        )

        let candidate = try AnthropicWebSearch.prepare(
            body: body,
            targetModel: "provider-model",
            configuration: .firecrawlCloud
        )
        let prepared = try #require(candidate)

        #expect(
            prepared.searchOptions
                == WebSearchFilterOptions(
                    includeDomains: ["swift.org", "github.com"],
                    location: "Paris, Ile-de-France",
                    country: "FR"
                )
        )
    }

    @Test("Search policy maps blocked domains")
    func blockedDomainOptions() throws {
        let body = Data(
            #"{"model":"claude","messages":[],"tools":[{"type":"web_search_20250305","blocked_domains":["example.com"]}]}"#
                .utf8
        )

        let candidate = try AnthropicWebSearch.prepare(
            body: body,
            targetModel: "provider-model",
            configuration: .firecrawlCloud
        )
        let prepared = try #require(candidate)
        #expect(prepared.searchOptions == WebSearchFilterOptions(excludeDomains: ["example.com"]))
    }

    @Test("Conflicting or malformed search policy is rejected before dispatch")
    func invalidSearchPolicy() throws {
        let tools = [
            #"{"type":"web_search_20250305","allowed_domains":[],"blocked_domains":[]}"#,
            #"{"type":"web_search_20250305","allowed_domains":[""]}"#,
            #"{"type":"web_search_20250305","blocked_domains":"example.com"}"#,
            #"{"type":"web_search_20250305","user_location":{"type":"precise","country":"FR"}}"#,
            #"{"type":"web_search_20250305","user_location":{"type":"approximate","country":42}}"#,
        ]

        for tool in tools {
            let body = Data(
                "{\"model\":\"claude\",\"stream\":true,\"messages\":[],\"tools\":[\(tool)]}".utf8
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

    @Test("Invalid or missing max_uses falls back to the configured bound")
    func maximumUsesFallback() throws {
        let toolVariants: [[String: Any]] = [
            ["type": "web_search_20250305"],
            ["type": "web_search_20250305", "max_uses": 0],
            ["type": "web_search_20250305", "max_uses": "many"],
        ]

        for tool in toolVariants {
            let body = try JSONSerialization.data(
                withJSONObject: ["model": "claude", "messages": [], "tools": [tool]]
            )
            let candidate = try AnthropicWebSearch.prepare(
                body: body,
                targetModel: "glm",
                configuration: WebSearchConfiguration(maximumUses: 4)
            )
            let prepared = try #require(candidate)
            #expect(prepared.maximumUses == 4)
        }
    }

    @Test("Request preparation rejects malformed protocol shapes")
    func malformedRequests() throws {
        let configuration = WebSearchConfiguration(maximumUses: 4)
        #expect(
            try AnthropicWebSearch.prepare(
                body: Data(#"{"model":"claude"}"#.utf8),
                targetModel: "glm",
                configuration: configuration
            ) == nil
        )
        for body in [#"{"model":"claude","tools":{}}"#, "[]", "{"] {
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                try AnthropicWebSearch.prepare(
                    body: Data(body.utf8),
                    targetModel: "glm",
                    configuration: configuration
                )
            }
        }
    }

    @Test("Model turns prefer the first valid search and preserve opaque content")
    func parsesModelTurn() throws {
        let body = Data(
            """
            {
              "id": "msg_provider",
              "model": "glm-5",
              "content": [
                {"type": "thinking", "thinking": "check"},
                {"type": "tool_use", "id": "weather_1", "name": "weather", "input": {"city": "Paris"}},
                {"type": "tool_use", "id": "search_1", "name": "web_search", "input": {"query": "Swift 6.2"}},
                {"type": "tool_use", "id": "search_2", "name": "web_search", "input": {"query": "ignored"}}
              ],
              "stop_reason": "tool_use",
              "stop_sequence": null,
              "usage": {"input_tokens": 11, "output_tokens": 7}
            }
            """.utf8
        )

        let turn = try AnthropicWebSearch.parseModelTurn(body)
        #expect(turn.id == "msg_provider")
        #expect(turn.stopReason == "tool_use")
        #expect(turn.stopSequenceJSON == Data("null".utf8))
        #expect(turn.usage == AnthropicUsage(inputTokens: 11, outputTokens: 7))
        #expect(turn.webSearchCall == WebSearchToolCall(id: "search_1", query: "Swift 6.2"))
        #expect((try JSONSerialization.jsonObject(with: turn.contentJSON) as? [Any])?.count == 4)
    }

    @Test("Empty or non-string search queries are surfaced for gateway error handling")
    func invalidQueries() throws {
        for input in [[:], ["query": 42]] as [[String: Any]] {
            let body = try JSONSerialization.data(
                withJSONObject: [
                    "id": "msg",
                    "content": [
                        [
                            "type": "tool_use",
                            "id": "search",
                            "name": "web_search",
                            "input": input,
                        ]
                    ],
                    "usage": ["input_tokens": 0, "output_tokens": 0],
                ]
            )
            #expect(
                try AnthropicWebSearch.parseModelTurn(body).webSearchCall?.query.isEmpty == true
            )
        }

        let missingID = Data(
            #"{"id":"msg","content":[{"type":"tool_use","name":"web_search","input":{"query":"Swift"}}],"usage":{"input_tokens":0,"output_tokens":0}}"#
                .utf8
        )
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try AnthropicWebSearch.parseModelTurn(missingID)
        }
    }

    @Test("Model turn parsing rejects every malformed required fragment")
    func malformedModelTurns() throws {
        let malformedBodies = [
            #"{"content":[],"usage":{}}"#,
            #"{"id":"msg","content":[42],"usage":{}}"#,
            #"{"id":"msg","content":[{}],"usage":{}}"#,
            #"{"id":"msg","content":[],"stop_reason":42,"usage":{}}"#,
            #"{"id":"msg","content":[],"usage":{"input_tokens":-1}}"#,
            #"{"id":"msg","content":[],"usage":{"output_tokens":"many"}}"#,
        ]
        for body in malformedBodies {
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                try AnthropicWebSearch.parseModelTurn(Data(body.utf8))
            }
        }
        let missingUsageCounts = try AnthropicWebSearch.parseModelTurn(
            Data(#"{"id":"msg","content":[],"usage":{}}"#.utf8)
        )
        #expect(missingUsageCounts.usage == AnthropicUsage(inputTokens: 0, outputTokens: 0))
        #expect(missingUsageCounts.stopReason == nil)
        #expect(missingUsageCounts.stopSequenceJSON == nil)
    }
}

extension AnthropicWebSearchTests {
    @Test("Follow-up messages contain only the selected search call and deterministic result")
    func followUpRequest() throws {
        let baseBody = Data(
            """
            {
              "model": "glm",
              "stream": false,
              "messages": [{"role": "user", "content": "latest Swift"}],
              "tools": [
                {"name": "web_search", "input_schema": {"type": "object"}},
                {"name": "weather", "input_schema": {"type": "object"}}
              ]
            }
            """.utf8
        )
        let content = Data(
            """
            [
              {"type": "thinking", "thinking": "check"},
              {"type": "text", "text": "I will search."},
              {"type": "tool_use", "id": "weather_1", "name": "weather", "input": {}},
              {"type": "tool_use", "id": "search_1", "name": "web_search", "input": {"query": "Swift"}}
            ]
            """.utf8
        )
        let turn = AnthropicModelTurn(
            id: "msg",
            contentJSON: content,
            stopReason: "tool_use",
            stopSequenceJSON: Data("null".utf8),
            usage: AnthropicUsage(inputTokens: 1, outputTokens: 2),
            webSearchCall: WebSearchToolCall(id: "search_1", query: "Swift")
        )
        let resultText = AnthropicWebSearch.formatResults([
            WebSearchResult(
                title: "Swift.org",
                url: "https://swift.org/",
                content: "The Swift project website"
            )
        ])
        #expect(
            resultText
                == "Title: Swift.org\nURL: https://swift.org/\nContent: The Swift project website\n\n"
        )

        let success = try AnthropicWebSearch.followUpRequest(
            baseBody: baseBody,
            turn: turn,
            toolCall: WebSearchToolCall(id: "search_1", query: "Swift"),
            resultText: resultText,
            mode: .result
        )
        let successObject = try anthropicWebSearchObject(success)
        let messages = try #require(successObject["messages"] as? [[String: Any]])
        #expect(messages.count == 3)
        let assistantContent = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(assistantContent.map { $0["type"] as? String } == ["thinking", "text", "tool_use"])
        #expect(assistantContent.last?["id"] as? String == "search_1")
        let resultContent = try #require(messages[2]["content"] as? [[String: Any]])
        #expect(resultContent.count == 1)
        #expect(resultContent[0]["type"] as? String == "tool_result")
        #expect(resultContent[0]["tool_use_id"] as? String == "search_1")
        #expect(resultContent[0]["content"] as? String == resultText)
        #expect(resultContent[0]["is_error"] == nil)

        let failure = try AnthropicWebSearch.followUpRequest(
            baseBody: baseBody,
            turn: turn,
            toolCall: WebSearchToolCall(id: "search_1", query: "Swift"),
            resultText: "unavailable",
            mode: .terminalError
        )
        let failureObject = try anthropicWebSearchObject(failure)
        let remainingTools = try #require(failureObject["tools"] as? [[String: Any]])
        #expect(remainingTools.map { $0["name"] as? String } == ["weather"])
        let failureMessages = try #require(failureObject["messages"] as? [[String: Any]])
        let failureContent = try #require(failureMessages.last?["content"] as? [[String: Any]])
        #expect(failureContent[0]["is_error"] as? Bool == true)
    }

    @Test("Follow-up rejects malformed history and mismatched search calls safely")
    func invalidFollowUp() throws {
        let validTurn = bareAnthropicTurn(
            contentJSON: Data(
                #"[{"type":"tool_use","id":"search_1","name":"web_search","input":{"query":"Swift"}}]"#
                    .utf8
            ),
            stopReason: "tool_use",
            webSearchCall: WebSearchToolCall(id: "search_1", query: "Swift")
        )
        let validBase = Data(#"{"messages":[]}"#.utf8)
        let validCall = WebSearchToolCall(id: "search_1", query: "Swift")
        let cases = [
            (Data(#"{"messages":{}}"#.utf8), validTurn, validCall),
            (validBase, validTurn, WebSearchToolCall(id: "different", query: "Swift")),
            (validBase, bareAnthropicTurn(contentJSON: Data("{".utf8)), validCall),
        ]
        for (baseBody, turn, toolCall) in cases {
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                try AnthropicWebSearch.followUpRequest(
                    baseBody: baseBody,
                    turn: turn,
                    toolCall: toolCall,
                    resultText: "result",
                    mode: .result
                )
            }
        }
    }
}

func anthropicWebSearchObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

func anthropicWebSearchData(_ value: Any) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: value,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
}

func bareAnthropicTurn(
    contentJSON: Data,
    stopReason: String? = nil,
    stopSequenceJSON: Data? = nil,
    webSearchCall: WebSearchToolCall? = nil
) -> AnthropicModelTurn {
    AnthropicModelTurn(
        id: "msg",
        contentJSON: contentJSON,
        stopReason: stopReason,
        stopSequenceJSON: stopSequenceJSON,
        usage: AnthropicUsage(inputTokens: 0, outputTokens: 0),
        webSearchCall: webSearchCall
    )
}
