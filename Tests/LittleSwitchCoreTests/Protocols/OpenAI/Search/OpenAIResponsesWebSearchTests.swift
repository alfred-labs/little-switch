import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses web search bridge")
// The suite keeps request, follow-up, usage, and projection contracts together.
// swiftlint:disable:next type_body_length
struct OpenAIResponsesWebSearchTests {
    @Test("Disabled search removes the provider declaration and preview search is bridged")
    func ineligibleRequests() throws {
        let searchBody = Data(
            #"{"model":"slug","input":"latest","tools":[{"type":"web_search"}]}"#.utf8
        )
        #expect(
            try OpenAIResponsesWebSearch.prepare(
                body: searchBody,
                targetModel: "provider-model",
                configuration: .disabled
            )?.maximumUses == 0
        )

        for type in ["web_search_preview", "web_search_preview_2025_03_11"] {
            let body = try JSONSerialization.data(
                withJSONObject: [
                    "model": "slug",
                    "input": "latest",
                    "tools": [["type": type]],
                ]
            )
            #expect(
                try OpenAIResponsesWebSearch.prepare(
                    body: body,
                    targetModel: "provider-model",
                    configuration: .firecrawlCloud
                ) != nil
            )
        }
    }

    @Test("Native search becomes one private function without losing opaque fields")
    func preparesPrivateFunction() throws {
        let body = Data(
            """
            {
              "model": "little-switch-slug",
              "input": "latest Swift",
              "stream": true,
              "reasoning": {"effort": "high"},
              "tools": [
                {"type": "web_search", "search_context_size": "high"},
                {"type": "function", "name": "web_search", "description": "collision", "parameters": {"type": "object"}},
                {"type": "function", "name": "weather", "parameters": {"type": "object"}}
              ],
              "unknown": [1, 2, 3]
            }
            """.utf8
        )

        let candidate = try OpenAIResponsesWebSearch.prepare(
            body: body,
            targetModel: "glm-5.3",
            configuration: .firecrawlCloud
        )
        let prepared = try #require(candidate)
        #expect(prepared.originalModel == "little-switch-slug")
        #expect(prepared.streaming)
        #expect(prepared.maximumUses == 3)

        let object = try responsesObject(prepared.upstreamBody)
        #expect(object["model"] as? String == "glm-5.3")
        #expect(object["input"] as? String == "latest Swift")
        #expect(object["stream"] as? Bool == false)
        #expect(object["reasoning"] as? [String: String] == ["effort": "high"])
        #expect(object["unknown"] as? [Int] == [1, 2, 3])

        let tools = try #require(object["tools"] as? [[String: Any]])
        #expect(tools.count == 3)
        #expect(tools.compactMap { $0["name"] as? String } == ["__little_switch_web_search", "web_search", "weather"])
        let search = try #require(tools.first)
        #expect(search["type"] as? String == "function")
        #expect(search["description"] as? String == "Search the web for current information.")
        let parameters = try #require(search["parameters"] as? [String: Any])
        #expect(parameters["type"] as? String == "object")
        #expect(parameters["required"] as? [String] == ["query"])
        let properties = try #require(parameters["properties"] as? [String: Any])
        #expect(
            properties["query"] as? [String: String]
                == ["type": "string", "description": "The search query."]
        )

        #expect(try responsesFragment(prepared.originalToolsJSON) is [Any])
        #expect(try responsesFragment(prepared.originalInputJSON) as? String == "latest Swift")
    }

    @Test("A private function call produces complete Responses history")
    func parsesAndBuildsFollowUp() throws {
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(
            Data(
                """
                {
                  "id": "resp_1",
                  "object": "response",
                  "created_at": 42,
                  "model": "glm-5.3",
                  "output": [
                    {"id": "rs_1", "type": "reasoning", "summary": []},
                    {
                      "id": "fc_search",
                      "type": "function_call",
                      "status": "completed",
                      "name": "web_search",
                      "call_id": "call_1",
                      "arguments": "{\\"query\\":\\"Swift 6.3\\"}"
                    },
                    {
                      "id": "fc_weather",
                      "type": "function_call",
                      "status": "completed",
                      "name": "weather",
                      "call_id": "call_2",
                      "arguments": "{\\"city\\":\\"Paris\\"}"
                    }
                  ],
                  "usage": {"input_tokens": 8, "output_tokens": 3, "total_tokens": 11}
                }
                """.utf8
            )
        )

        #expect(
            turn.webSearchCall
                == ResponsesWebSearchToolCall(callID: "call_1", query: "Swift 6.3")
        )
        #expect(turn.usage == ResponsesUsage(inputTokens: 8, outputTokens: 3))

        let prepared = try preparedRequest(input: "latest Swift")
        let followUp = try OpenAIResponsesWebSearch.followUpRequest(
            baseBody: prepared.upstreamBody,
            turn: turn,
            toolCall: try #require(turn.webSearchCall),
            resultText: "Title: Swift\nURL: https://swift.org\nContent: Current\n\n",
            mode: .result
        )
        let object = try responsesObject(followUp)
        let input = try #require(object["input"] as? [[String: Any]])
        #expect(
            input.compactMap { $0["type"] as? String }
                == ["message", "reasoning", "function_call", "function_call", "function_call_output"]
        )
        let message = try #require(input.first)
        #expect(message["role"] as? String == "user")
        let content = try #require(message["content"] as? [[String: String]])
        #expect(content == [["type": "input_text", "text": "latest Swift"]])
        let output = try #require(input.last)
        #expect(output["call_id"] as? String == "call_1")
        #expect(output["output"] as? String == "Title: Swift\nURL: https://swift.org\nContent: Current\n\n")
    }

    @Test("Array input stays ordered and terminal errors remove only private search")
    func arrayInputAndTerminalError() throws {
        let prepared = try preparedRequest(
            input: [["type": "message", "role": "user", "content": "existing"]]
        )
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(
            Data(
                """
                {
                  "id": "resp_2",
                  "output": [
                    {
                      "id": "fc_search",
                      "type": "function_call",
                      "name": "web_search",
                      "call_id": "call_2",
                      "arguments": "{}"
                    }
                  ],
                  "usage": {"input_tokens": 1, "output_tokens": 2}
                }
                """.utf8
            )
        )
        let call = try #require(turn.webSearchCall)
        #expect(call.query.isEmpty)

        let followUp = try OpenAIResponsesWebSearch.followUpRequest(
            baseBody: prepared.upstreamBody,
            turn: turn,
            toolCall: call,
            resultText: "invalid_request",
            mode: .terminalError
        )
        let object = try responsesObject(followUp)
        let input = try #require(object["input"] as? [[String: Any]])
        #expect(input.compactMap { $0["type"] as? String } == ["message", "function_call", "function_call_output"])
        #expect(input.first?["content"] as? String == "existing")
        let tools = try #require(object["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == ["weather"])
    }

    @Test("A follow-up removes unselected private searches from the model history")
    func followUpFiltersParallelPrivateSearches() throws {
        let prepared = try preparedRequest(input: "latest Swift")
        let turnBody = try JSONSerialization.data(
            withJSONObject: [
                "id": "resp_parallel",
                "output": [
                    privateSearchCall(
                        id: "fc_first",
                        callID: "call_first",
                        query: "first"
                    ),
                    privateSearchCall(
                        id: "fc_second",
                        callID: "call_second",
                        query: "second"
                    ),
                    [
                        "id": "fc_weather",
                        "type": "function_call",
                        "name": "weather",
                        "call_id": "call_weather",
                        "arguments": #"{"city":"Paris"}"#,
                    ],
                ],
                "usage": [:],
            ]
        )
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(turnBody)

        let followUp = try OpenAIResponsesWebSearch.followUpRequest(
            baseBody: prepared.upstreamBody,
            turn: turn,
            toolCall: try #require(turn.webSearchCall),
            resultText: "result",
            mode: .result
        )
        let object = try responsesObject(followUp)
        let input = try #require(object["input"] as? [[String: Any]])
        let calls = input.filter { $0["type"] as? String == "function_call" }

        #expect(calls.compactMap { $0["call_id"] as? String } == ["call_first", "call_weather"])
        #expect(
            input.filter { $0["type"] as? String == "function_call_output" }
                .compactMap { $0["call_id"] as? String } == ["call_first"]
        )
    }

    @Test("Responses usage addition saturates")
    func usageSaturates() {
        var usage = ResponsesUsage(inputTokens: Int.max, outputTokens: 4)
        usage.add(ResponsesUsage(inputTokens: 1, outputTokens: Int.max))
        #expect(usage == ResponsesUsage(inputTokens: Int.max, outputTokens: Int.max))
    }

    @Test("Projection hides private calls and orders native search items")
    // This full-value fixture locks the shell and all four supported output families together.
    // swiftlint:disable:next function_body_length
    func nonStreamingProjection() throws {
        let prepared = try preparedRequest(input: "latest Swift")
        let searchTurn = try responsesTurn(
            id: "resp_search",
            output: [
                [
                    "id": "rs_1",
                    "type": "reasoning",
                    "summary": [],
                    "content": [["type": "reasoning_text", "text": "Safe reasoning"]],
                    "encrypted_content": "opaque-replay-token",
                    "provider_secret": "provider-secret-reasoning-item",
                ],
                [
                    "id": "fc_search",
                    "type": "function_call",
                    "status": "completed",
                    "name": "web_search",
                    "call_id": "call_1",
                    "arguments": #"{"query":"Swift 6.3"}"#,
                ],
                [
                    "id": "fc_weather",
                    "type": "function_call",
                    "status": "completed",
                    "name": "weather",
                    "call_id": "call_2",
                    "arguments": #"{"city":"Paris"}"#,
                    "namespace": "tools",
                    "provider_secret": "provider-secret-function-item",
                ],
            ]
        )
        let finalTurn = try responsesTurn(
            id: "resp_final",
            output: [
                [
                    "id": "msg_1",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "phase": "final_answer",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "Swift is current.",
                            "annotations": [
                                [
                                    "type": "url_citation",
                                    "start_index": 0,
                                    "end_index": 5,
                                    "title": "Swift",
                                    "url": "https://swift.org/",
                                    "provider_secret": "provider-secret-annotation",
                                ]
                            ],
                            "logprobs": [
                                [
                                    "token": "Swift",
                                    "logprob": -0.1,
                                    "bytes": [83],
                                    "provider_secret": "provider-secret-logprob",
                                ]
                            ],
                            "provider_secret": "provider-secret-content-part",
                        ]
                    ],
                    "internal_chat_message_metadata_passthrough": [
                        "turn_id": "turn_final",
                        "provider_secret": "provider-secret-message-metadata",
                    ],
                    "provider_secret": "provider-secret-message-item",
                ],
                [
                    "id": "fc_other",
                    "type": "function_call",
                    "status": "completed",
                    "name": "calendar",
                    "call_id": "call_3",
                    "arguments": "{}",
                    "namespace": "apps",
                    "provider_secret": "provider-secret-final-function-item",
                ],
            ],
            completedAt: 45,
            unknown: ["preserved": true]
        )
        let trace = ResponsesWebSearchTrace(
            id: "ws_1",
            callID: "call_1",
            query: "Swift 6.3",
            outputJSON: searchTurn.outputJSON
        )

        let data = try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: prepared,
            traces: [trace],
            finalTurn: finalTurn,
            usage: ResponsesUsage(inputTokens: 20, outputTokens: 9)
        )
        let response = try responsesObject(data)
        #expect(response["id"] as? String == "resp_final")
        #expect(response["model"] as? String == "little-switch-slug")
        #expect(response["status"] as? String == "completed")
        #expect(response["completed_at"] as? Int == 45)
        #expect(response["unknown"] == nil)
        #expect(response["metadata"] as? [String: String] == ["owner": "client"])
        #expect(response["parallel_tool_calls"] as? Bool == true)
        let tools = try #require(response["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["type"] as? String } == ["web_search", "function"])

        let output = try #require(response["output"] as? [[String: Any]])
        #expect(
            output.compactMap { $0["type"] as? String }
                == ["reasoning", "web_search_call", "function_call", "message", "function_call"]
        )
        #expect(output.allSatisfy { $0["name"] as? String != "web_search" })
        let serialized = try #require(String(data: data, encoding: .utf8))
        #expect(!serialized.contains("provider-secret"))
        let reasoning = try #require(output.first)
        #expect(reasoning["encrypted_content"] as? String == "opaque-replay-token")
        #expect(
            reasoning["content"] as? [[String: String]]
                == [["type": "reasoning_text", "text": "Safe reasoning"]]
        )
        let weather = try #require(output.first { $0["id"] as? String == "fc_weather" })
        #expect(weather["namespace"] as? String == "tools")
        let message = try #require(output.first { $0["id"] as? String == "msg_1" })
        #expect(message["phase"] as? String == "final_answer")
        #expect(
            message["internal_chat_message_metadata_passthrough"] as? [String: String]
                == ["turn_id": "turn_final"]
        )
        let search = try #require(output[1] as [String: Any]?)
        #expect(search["id"] as? String == "ws_1")
        #expect(search["status"] as? String == "completed")
        #expect(
            search["action"] as? [String: String]
                == ["type": "search", "query": "Swift 6.3"]
        )
        try expectDefaultResponsesUsage(response["usage"], 20, 9, 29)
    }
}

private func preparedRequest(input: Any) throws -> PreparedResponsesWebSearchRequest {
    let body = try JSONSerialization.data(
        withJSONObject: [
            "model": "little-switch-slug",
            "input": input,
            "stream": false,
            "metadata": ["owner": "client"],
            "parallel_tool_calls": true,
            "tools": [
                ["type": "web_search"],
                ["type": "function", "name": "weather", "parameters": ["type": "object"]],
            ],
        ],
        options: [.sortedKeys]
    )
    return try #require(
        try OpenAIResponsesWebSearch.prepare(
            body: body,
            targetModel: "glm-5.3",
            configuration: .firecrawlCloud
        )
    )
}

private func privateSearchCall(
    id: String,
    callID: String,
    query: String
) -> [String: Any] {
    [
        "id": id,
        "type": "function_call",
        "name": "web_search",
        "call_id": callID,
        "arguments": #"{"query":"\#(query)"}"#,
    ]
}

private func responsesObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func responsesFragment(_ data: Data) throws -> Any {
    try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}

private func responsesTurn(
    id: String,
    output: [[String: Any]],
    completedAt: Int? = nil,
    unknown: [String: Bool]? = nil
) throws -> ResponsesModelTurn {
    var object: [String: Any] = [
        "id": id,
        "object": "response",
        "created_at": 40,
        "status": "completed",
        "model": "glm-5.3",
        "output": output,
        "tools": [["type": "function", "name": "web_search"]],
        "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
    ]
    if let completedAt {
        object["completed_at"] = completedAt
    }
    if let unknown {
        object["unknown"] = unknown
        object["metadata"] = [
            "owner": "provider",
            "provider_secret": "provider-secret-root-metadata",
        ]
        object["parallel_tool_calls"] = false
        object["provider_secret"] = "provider-secret-root"
    }
    return try OpenAIResponsesWebSearch.parseModelTurn(
        JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
}
