import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI projection coverage edges")
struct OpenAIProjectionCoverageEdgeTests {
    @Test("Streaming encoder covers all terminal and item families")
    func bufferedStreamingEncoderMatrix() throws {
        let output: [[String: Any]] = [
            [
                "id": "ws", "type": "web_search_call", "status": "completed",
                "action": ["type": "search", "query": "q"],
            ],
            [
                "id": "rs", "type": "reasoning",
                "summary": [
                    ["type": "summary_text", "text": ""],
                    ["type": "summary_text", "text": "reason"],
                ],
            ],
            [
                "id": "msg", "type": "message", "role": "assistant", "status": "completed",
                "content": [
                    ["type": "refusal", "refusal": "No"],
                    outputTextPart(""),
                ],
            ],
            functionCallItem(
                id: "fc", callID: "call", name: "read", arguments: "", status: "completed"
            ),
        ]
        for status in ["completed", "incomplete"] {
            let data = try OpenAIResponsesStreaming.encode(completed: [
                "id": "resp_\(status)",
                "object": "response",
                "status": status,
                "output": output,
                "usage": [:],
            ])
            #expect(!data.isEmpty)
        }
        #expect(
            try !OpenAIResponsesStreaming.encode(completed: [
                "id": "resp_empty_reasoning",
                "object": "response",
                "status": "completed",
                "output": [["id": "rs_empty", "type": "reasoning"]],
                "usage": [:],
            ]).isEmpty
        )
        for code in ["context_length_exceeded", "private"] {
            let data = try OpenAIResponsesStreaming.encode(completed: [
                "id": "resp_failed", "object": "response", "status": "failed", "output": [],
                "error": ["code": code, "message": "private"],
            ])
            let stream = try #require(String(bytes: data, encoding: .utf8))
            #expect(stream.contains("response.failed"))
        }

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesStreaming.encode(completed: [:])
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesStreaming.encode(completed: [
                "status": "queued", "output": [],
            ])
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesStreaming.encode(completed: [
                "status": "completed", "output": [["type": "unknown"]],
            ])
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesStreaming.encode(completed: [
                "status": "completed",
                "output": [
                    [
                        "id": "msg", "type": "message", "role": "assistant",
                        "content": "bad",
                    ]
                ],
            ])
        }
    }

    @Test("Request and projection boundaries reject malformed optional fields")
    func requestAndProjectionEdges() throws {
        let base: [String: Any] = [
            "model": "route", "input": "q", "tools": [["type": "web_search"]],
        ]
        let missingDomains = base.merging([
            "tools": [["type": "web_search", "filters": [:]]]
        ]) { _, new in new }
        #expect(
            try OpenAIResponsesWebSearch.prepare(
                body: responseData(missingDomains),
                targetModel: "provider",
                configuration: .firecrawlCloud
            ) != nil
        )
        for badTool: [String: Any] in [
            ["type": "web_search", "filters": ["allowed_domains": "bad"]],
            ["type": "web_search", "filters": ["allowed_domains": [" "]]],
            ["type": "web_search", "user_location": ["type": "exact"]],
            ["type": "web_search", "user_location": ["type": "approximate", "city": 1]],
            ["type": "web_search", "user_location": ["type": "approximate", "city": " "]],
        ] {
            var body = base
            body["tools"] = [badTool]
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try OpenAIResponsesWebSearch.prepare(
                    body: responseData(body),
                    targetModel: "provider",
                    configuration: .firecrawlCloud
                )
            }
        }

        var usageMissingDetails = responseObject(
            id: "resp",
            createdAt: 1,
            status: "completed",
            output: [],
            usage: .init(inputTokens: 1, outputTokens: 1)
        )
        usageMissingDetails["usage"] = [
            "input_tokens": 1,
            "output_tokens": 1,
            "input_tokens_details": [:],
            "output_tokens_details": ["reasoning_tokens": 0],
        ]
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesWebSearch.parseModelTurn(responseData(usageMissingDetails))
        }

        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: responseData(base),
                targetModel: "provider",
                configuration: .firecrawlCloud
            )
        )
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(
            responseData(
                responseObject(
                    id: "resp",
                    createdAt: 1,
                    status: "completed",
                    output: [],
                    usage: .init(inputTokens: 0, outputTokens: 0)
                )
            )
        )
        let invalidPrepared = PreparedResponsesWebSearchRequest(
            upstreamBody: prepared.upstreamBody,
            originalBody: prepared.originalBody,
            originalModel: prepared.originalModel,
            originalToolsJSON: try responseData("not-an-array"),
            originalInputJSON: prepared.originalInputJSON,
            streaming: false,
            maximumUses: prepared.maximumUses
        )
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesWebSearch.projectedResponse(
                prepared: invalidPrepared,
                traces: [],
                finalTurn: turn,
                usage: .init(inputTokens: 0, outputTokens: 0)
            )
        }

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesPublicSanitizer.clientResponseFields(
                originalBody: responseData(base),
                originalModel: "other"
            )
        }
    }

    @Test("Chat projection rejects malformed response shapes")
    func chatProjectionEdges() throws {
        let prepared = try liveChatPrepared(includeTools: false)
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try OpenAIResponsesChatCompletions.terminalStatus(responseBody: responseData([:]))
        }

        func project(_ message: [String: Any]) throws -> Data {
            try OpenAIResponsesChatCompletions.project(
                responseBody: responseData([
                    "id": "chat",
                    "choices": [["finish_reason": "stop", "message": message]],
                    "usage": NSNull(),
                ]),
                prepared: prepared
            )
        }

        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try project(["content": 1])
        }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try project([
                "content": NSNull(),
                "tool_calls": [["id": "call", "type": "private"]],
            ])
        }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try OpenAIResponsesChatCompletions.responsesUsage("bad")
        }
    }
}
