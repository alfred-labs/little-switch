import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Native cumulative usage parity")
struct NativeUsageParityTests {
    @Test("Anthropic model-search-model usage preserves every caller-consumed detail")
    func anthropicCumulativeUsage() throws {
        let searchedTurn = try anthropicTurn(
            id: "msg_search",
            content: [
                [
                    "type": "tool_use",
                    "id": "toolu_search",
                    "name": "web_search",
                    "input": ["query": "Swift 6.3"],
                ]
            ],
            stopReason: "tool_use",
            usage: [
                "input_tokens": 13,
                "output_tokens": 4,
                "cache_creation_input_tokens": 3,
                "cache_read_input_tokens": 5,
                "cache_creation": [
                    "ephemeral_1h_input_tokens": 2,
                    "ephemeral_5m_input_tokens": 1,
                ],
                "service_tier": "standard",
            ]
        )
        let finalTurn = try anthropicTurn(
            id: "msg_final",
            content: [["type": "text", "text": "Current answer"]],
            stopReason: "end_turn",
            usage: [
                "input_tokens": 29,
                "output_tokens": 9,
                "cache_creation_input_tokens": 7,
                "cache_read_input_tokens": 11,
                "cache_creation": [
                    "ephemeral_1h_input_tokens": 4,
                    "ephemeral_5m_input_tokens": 3,
                ],
                "service_tier": "priority",
            ]
        )

        var usage = searchedTurn.usage
        usage.add(finalTurn.usage)
        let response = try AnthropicWebSearch.nonStreamingResponse(
            originalModel: "claude-route",
            traces: [
                WebSearchTrace(
                    toolUseID: "toolu_search",
                    query: "Swift 6.3",
                    content: .results([])
                )
            ],
            finalTurn: finalTurn,
            usage: usage
        )

        let root = try nativeUsageObject(response)
        let terminalUsage = try #require(root["usage"] as? [String: Any])
        #expect(
            NSDictionary(dictionary: terminalUsage).isEqual(to: [
                "input_tokens": 42,
                "output_tokens": 13,
                "cache_creation_input_tokens": 10,
                "cache_read_input_tokens": 16,
                "cache_creation": [
                    "ephemeral_1h_input_tokens": 6,
                    "ephemeral_5m_input_tokens": 4,
                ],
                "service_tier": "priority",
                "server_tool_use": [
                    "web_search_requests": 1,
                    "web_fetch_requests": 0,
                ],
            ])
        )
    }

    @Test("Responses model-search-model usage preserves native token details and total")
    func responsesCumulativeUsage() throws {
        let searchedTurn = try responsesTurn(
            id: "resp_search",
            output: [
                [
                    "id": "fc_search",
                    "type": "function_call",
                    "name": "web_search",
                    "call_id": "call_search",
                    "arguments": #"{"query":"Swift 6.3"}"#,
                ]
            ],
            usage: [
                "input_tokens": 11,
                "input_tokens_details": [
                    "cached_tokens": 4,
                    "cache_write_tokens": 2,
                ],
                "output_tokens": 3,
                "output_tokens_details": ["reasoning_tokens": 1],
                "total_tokens": 14,
            ]
        )
        let finalTurn = try responsesTurn(
            id: "resp_final",
            output: [
                [
                    "id": "msg_final",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "Current answer",
                            "annotations": [],
                        ]
                    ],
                ]
            ],
            usage: [
                "input_tokens": 23,
                "input_tokens_details": [
                    "cached_tokens": 7,
                    "cache_write_tokens": 5,
                ],
                "output_tokens": 8,
                "output_tokens_details": ["reasoning_tokens": 6],
                "total_tokens": 31,
            ]
        )

        var usage = searchedTurn.usage
        usage.add(finalTurn.usage)
        let response = try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: try preparedResponsesSearch(),
            traces: [],
            finalTurn: finalTurn,
            usage: usage
        )

        let root = try nativeUsageObject(response)
        let terminalUsage = try #require(root["usage"] as? [String: Any])
        #expect(
            NSDictionary(dictionary: terminalUsage).isEqual(to: [
                "input_tokens": 34,
                "input_tokens_details": [
                    "cached_tokens": 11,
                    "cache_write_tokens": 7,
                ],
                "output_tokens": 11,
                "output_tokens_details": ["reasoning_tokens": 7],
                "total_tokens": 45,
            ])
        )
    }

}

@Suite("Native cumulative usage safety")
struct NativeUsageSafetyTests {
    @Test("Every cumulative usage counter saturates")
    func cumulativeUsageSaturates() throws {
        let anthropicMaximum = try anthropicTurn(
            id: "msg_max",
            content: [],
            stopReason: "end_turn",
            usage: [
                "input_tokens": Int.max - 1,
                "output_tokens": Int.max - 1,
                "cache_creation_input_tokens": Int.max - 1,
                "cache_read_input_tokens": Int.max - 1,
                "cache_creation": [
                    "ephemeral_1h_input_tokens": Int.max - 1,
                    "ephemeral_5m_input_tokens": Int.max - 1,
                ],
            ]
        )
        let anthropicIncrement = try anthropicTurn(
            id: "msg_increment",
            content: [],
            stopReason: "end_turn",
            usage: [
                "input_tokens": 2,
                "output_tokens": 2,
                "cache_creation_input_tokens": 2,
                "cache_read_input_tokens": 2,
                "cache_creation": [
                    "ephemeral_1h_input_tokens": 2,
                    "ephemeral_5m_input_tokens": 2,
                ],
            ]
        )
        var anthropicUsage = anthropicMaximum.usage
        anthropicUsage.add(anthropicIncrement.usage)
        let anthropicResponse = try AnthropicWebSearch.nonStreamingResponse(
            originalModel: "claude-route",
            traces: [],
            finalTurn: anthropicIncrement,
            usage: anthropicUsage
        )
        let anthropicTerminal = try #require(
            nativeUsageObject(anthropicResponse)["usage"] as? [String: Any]
        )
        #expect(anthropicTerminal["input_tokens"] as? Int == Int.max)
        #expect(anthropicTerminal["output_tokens"] as? Int == Int.max)
        #expect(anthropicTerminal["cache_creation_input_tokens"] as? Int == Int.max)
        #expect(anthropicTerminal["cache_read_input_tokens"] as? Int == Int.max)
        let cacheCreation = try #require(
            anthropicTerminal["cache_creation"] as? [String: Int]
        )
        #expect(cacheCreation["ephemeral_1h_input_tokens"] == Int.max)
        #expect(cacheCreation["ephemeral_5m_input_tokens"] == Int.max)

        let responsesMaximum = try responsesTurn(
            id: "resp_max",
            output: [],
            usage: [
                "input_tokens": Int.max - 1,
                "input_tokens_details": [
                    "cached_tokens": Int.max - 1,
                    "cache_write_tokens": Int.max - 1,
                ],
                "output_tokens": Int.max - 1,
                "output_tokens_details": ["reasoning_tokens": Int.max - 1],
                "total_tokens": Int.max - 1,
            ]
        )
        let responsesIncrement = try responsesTurn(
            id: "resp_increment",
            output: [],
            usage: [
                "input_tokens": 2,
                "input_tokens_details": [
                    "cached_tokens": 2,
                    "cache_write_tokens": 2,
                ],
                "output_tokens": 2,
                "output_tokens_details": ["reasoning_tokens": 2],
                "total_tokens": 2,
            ]
        )
        var responsesUsage = responsesMaximum.usage
        responsesUsage.add(responsesIncrement.usage)
        let responsesTerminal = try nativeUsageObject(
            JSONSerialization.data(withJSONObject: responsesPublicUsage(responsesUsage))
        )
        #expect(responsesTerminal["input_tokens"] as? Int == Int.max)
        #expect(responsesTerminal["output_tokens"] as? Int == Int.max)
        #expect(responsesTerminal["total_tokens"] as? Int == Int.max)
        let inputDetails = try #require(
            responsesTerminal["input_tokens_details"] as? [String: Int]
        )
        #expect(inputDetails["cached_tokens"] == Int.max)
        #expect(inputDetails["cache_write_tokens"] == Int.max)
        let outputDetails = try #require(
            responsesTerminal["output_tokens_details"] as? [String: Int]
        )
        #expect(outputDetails["reasoning_tokens"] == Int.max)
    }

    @Test("Optional usage detail objects may be absent but malformed details are rejected")
    func detailValidation() throws {
        _ = try anthropicTurn(
            id: "msg_without_details",
            content: [],
            stopReason: "end_turn",
            usage: ["input_tokens": 1, "output_tokens": 2]
        )
        _ = try responsesTurn(
            id: "resp_without_details",
            output: [],
            usage: ["input_tokens": 1, "output_tokens": 2, "total_tokens": 3]
        )

        let malformedAnthropicUsage: [[String: Any]] = [
            ["cache_creation_input_tokens": -1],
            ["cache_read_input_tokens": "1"],
            ["cache_creation": []],
            ["cache_creation": ["ephemeral_1h_input_tokens": 1]],
            ["cache_creation": ["ephemeral_1h_input_tokens": -1]],
            ["service_tier": "turbo"],
        ]
        for usage in malformedAnthropicUsage {
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                _ = try anthropicTurn(
                    id: "msg_invalid",
                    content: [],
                    stopReason: "end_turn",
                    usage: usage
                )
            }
        }

        let malformedResponsesUsage: [[String: Any]] = [
            ["input_tokens_details": []],
            ["input_tokens_details": ["cached_tokens": -1]],
            [
                "input_tokens_details": [
                    "cached_tokens": 1,
                    "cache_write_tokens": "2",
                ]
            ],
            ["output_tokens_details": ["reasoning_tokens": -1]],
            ["total_tokens": -1],
        ]
        for usage in malformedResponsesUsage {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try responsesTurn(
                    id: "resp_invalid",
                    output: [],
                    usage: usage
                )
            }
        }
    }

}

@Suite("Z.AI Chat usage parity")
struct ZAIChatUsageParityTests {
    @Test("Z.AI Chat usage maps prompt details without exposing reasoning content")
    func zaiChatUsageAndPrivacy() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: Data(#"{"model":"route","input":"Hello","stream":false}"#.utf8),
            targetModel: "glm-5"
        )
        let response = try OpenAIResponsesChatCompletions.project(
            responseBody: Data(
                #"""
                {
                  "id":"chatcmpl_usage",
                  "created":42,
                  "choices":[
                    {
                      "finish_reason":"stop",
                      "message":{
                        "role":"assistant",
                        "content":"Answer",
                        "reasoning_content":"private chain of thought"
                      }
                    }
                  ],
                  "usage":{
                    "prompt_tokens":12,
                    "prompt_tokens_details":{
                      "cached_tokens":5,
                      "cache_write_tokens":2
                    },
                    "completion_tokens":4,
                    "completion_tokens_details":{"reasoning_tokens":3},
                    "total_tokens":16
                  }
                }
                """#.utf8
            ),
            prepared: prepared
        )

        let root = try nativeUsageObject(response)
        let usage = try #require(root["usage"] as? [String: Any])
        #expect(
            NSDictionary(dictionary: usage).isEqual(to: [
                "input_tokens": 12,
                "input_tokens_details": [
                    "cached_tokens": 5,
                    "cache_write_tokens": 2,
                ],
                "output_tokens": 4,
                "output_tokens_details": ["reasoning_tokens": 3],
                "total_tokens": 16,
            ])
        )
        let publicJSON = try #require(String(data: response, encoding: .utf8))
        #expect(!publicJSON.contains("reasoning_content"))
        #expect(!publicJSON.contains("private chain of thought"))
    }

    @Test("Z.AI Chat rejects malformed usage detail objects")
    func zaiChatUsageValidation() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: Data(#"{"model":"route","input":"Hello","stream":false}"#.utf8),
            targetModel: "glm-5"
        )
        for usage in [
            #"{"prompt_tokens":1,"completion_tokens":1,"prompt_tokens_details":[]}"#,
            #"{"prompt_tokens":1,"completion_tokens":1,"prompt_tokens_details":{"cached_tokens":-1}}"#,
            #"{"prompt_tokens":1,"completion_tokens":1,"completion_tokens_details":{"reasoning_tokens":"1"}}"#,
        ] {
            let response = Data(
                """
                {
                  "id":"chatcmpl_invalid_usage",
                  "choices":[
                    {"finish_reason":"stop","message":{"role":"assistant","content":"Answer"}}
                  ],
                  "usage":\(usage)
                }
                """.utf8
            )
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
                _ = try OpenAIResponsesChatCompletions.project(
                    responseBody: response,
                    prepared: prepared
                )
            }
        }
    }
}

private func anthropicTurn(
    id: String,
    content: [[String: Any]],
    stopReason: String,
    usage: [String: Any]
) throws -> AnthropicModelTurn {
    try AnthropicWebSearch.parseModelTurn(
        try JSONSerialization.data(
            withJSONObject: [
                "id": id,
                "content": content,
                "stop_reason": stopReason,
                "stop_sequence": NSNull(),
                "usage": usage,
            ]
        )
    )
}

private func responsesTurn(
    id: String,
    output: [[String: Any]],
    usage: [String: Any]
) throws -> ResponsesModelTurn {
    try OpenAIResponsesWebSearch.parseModelTurn(
        try JSONSerialization.data(
            withJSONObject: [
                "id": id,
                "object": "response",
                "status": "completed",
                "model": "provider-model",
                "output": output,
                "usage": usage,
            ]
        )
    )
}

private func preparedResponsesSearch() throws -> PreparedResponsesWebSearchRequest {
    let candidate = try OpenAIResponsesWebSearch.prepare(
        body: Data(
            #"{"model":"route","input":"Question","tools":[{"type":"web_search"}]}"#.utf8
        ),
        targetModel: "provider-model",
        configuration: .firecrawlCloud
    )
    return try #require(candidate)
}

private func nativeUsageObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
