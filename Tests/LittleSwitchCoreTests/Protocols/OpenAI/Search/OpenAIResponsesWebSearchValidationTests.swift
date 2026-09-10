import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses web search validation")
struct OpenAIResponsesWebSearchValidationTests {
    @Test("Preparation distinguishes absent tools from malformed eligible shapes")
    func preparationValidation() throws {
        #expect(
            try OpenAIResponsesWebSearch.prepare(
                body: Data(#"{"model":"slug","input":"x"}"#.utf8),
                targetModel: "target",
                configuration: .firecrawlCloud
            ) == nil
        )
        for body in [
            #"{"model":"slug","input":"x","tools":{}}"#,
            #"{"model":"slug","tools":[{"type":"web_search"}]}"#,
            #"{"model":"slug","input":7,"tools":[{"type":"web_search"}]}"#,
            "[]",
            "{",
        ] {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesWebSearch.prepare(
                    body: Data(body.utf8),
                    targetModel: "target",
                    configuration: .firecrawlCloud
                )
            }
        }

        let withoutStreamCandidate = try OpenAIResponsesWebSearch.prepare(
            body: Data(
                #"{"model":"slug","input":"x","tools":[{"type":"web_search"}]}"#.utf8
            ),
            targetModel: "target",
            configuration: .firecrawlCloud
        )
        let withoutStream = try #require(withoutStreamCandidate)
        #expect(withoutStream.streaming == false)
    }

    @Test("Turn parsing validates items, call IDs, usage, and malformed arguments")
    func turnValidation() throws {
        for body in [
            "[]",
            "{",
            #"{"id":"resp","output":[{}],"usage":{}}"#,
            #"{"id":"resp","output":[{"type":"function_call","name":"web_search"}],"usage":{}}"#,
            #"{"id":"resp","output":[],"usage":{"input_tokens":-1}}"#,
        ] {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesWebSearch.parseModelTurn(Data(body.utf8))
            }
        }

        let missingUsage = try OpenAIResponsesWebSearch.parseModelTurn(
            Data(#"{"id":"resp","output":[],"usage":{}}"#.utf8)
        )
        #expect(missingUsage.usage == ResponsesUsage(inputTokens: 0, outputTokens: 0))
        let malformedArguments = try OpenAIResponsesWebSearch.parseModelTurn(
            Data(
                #"{"id":"resp","output":[{"type":"function_call","name":"web_search","call_id":"call","arguments":"{"}],"usage":{}}"#
                    .utf8
            )
        )
        #expect(malformedArguments.webSearchCall?.query.isEmpty == true)
    }

    @Test("Follow-up rejects mismatched calls, invalid input, and invalid stored output")
    func followUpValidation() throws {
        let prepared = try validationPrepared()
        let turn = try validationSearchTurn()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesWebSearch.followUpRequest(
                baseBody: prepared.upstreamBody,
                turn: turn,
                toolCall: ResponsesWebSearchToolCall(callID: "other", query: "Swift"),
                resultText: "result",
                mode: .result
            )
        }

        var invalidInput = try validationObject(prepared.upstreamBody)
        invalidInput["input"] = 7
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesWebSearch.followUpRequest(
                baseBody: try JSONSerialization.data(withJSONObject: invalidInput),
                turn: turn,
                toolCall: try #require(turn.webSearchCall),
                resultText: "result",
                mode: .result
            )
        }

        for output in [Data("null".utf8), Data("{".utf8)] {
            let invalidTurn = ResponsesModelTurn(
                id: "resp",
                rootJSON: Data("{}".utf8),
                outputJSON: output,
                usage: ResponsesUsage(inputTokens: 0, outputTokens: 0),
                webSearchCall: nil
            )
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesWebSearch.followUpRequest(
                    baseBody: prepared.upstreamBody,
                    turn: invalidTurn,
                    toolCall: ResponsesWebSearchToolCall(callID: "call", query: "Swift"),
                    resultText: "result",
                    mode: .result
                )
            }
        }
    }

    @Test("Projection rejects corrupted state and removes duplicate private calls")
    func projectionValidation() throws {
        let prepared = try validationPrepared()
        let finalTurn = try validationFinalTurn(output: [])
        let duplicateOutput = try JSONSerialization.data(
            withJSONObject: [validationSearchItem(), validationSearchItem()]
        )
        let duplicateTrace = ResponsesWebSearchTrace(
            id: "ws_1",
            callID: "call_search",
            query: "Swift",
            outputJSON: duplicateOutput
        )
        let projected = try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: prepared,
            traces: [duplicateTrace],
            finalTurn: finalTurn,
            usage: ResponsesUsage(inputTokens: Int.max, outputTokens: 1)
        )
        let object = try validationObject(projected)
        let output = try #require(object["output"] as? [[String: Any]])
        #expect(output.count == 1)
        #expect((object["usage"] as? [String: Any])?["total_tokens"] as? Int == Int.max)

        let mismatch = ResponsesWebSearchTrace(
            id: "ws_1",
            callID: "other",
            query: "Swift",
            outputJSON: try JSONSerialization.data(withJSONObject: [validationSearchItem()])
        )
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesWebSearch.nonStreamingResponse(
                prepared: prepared,
                traces: [mismatch],
                finalTurn: finalTurn,
                usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
            )
        }

        for invalidOutput in [Data("null".utf8), Data("{".utf8)] {
            let trace = ResponsesWebSearchTrace(
                id: "ws_1",
                callID: "call_search",
                query: "Swift",
                outputJSON: invalidOutput
            )
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesWebSearch.nonStreamingResponse(
                    prepared: prepared,
                    traces: [trace],
                    finalTurn: finalTurn,
                    usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
                )
            }
        }
    }

    @Test("Projection rejects invalid roots and original tool fragments")
    func projectionRootValidation() throws {
        let prepared = try validationPrepared()
        for root in [Data("[]".utf8), Data("{".utf8)] {
            let invalidTurn = ResponsesModelTurn(
                id: "resp",
                rootJSON: root,
                outputJSON: Data("[]".utf8),
                usage: ResponsesUsage(inputTokens: 0, outputTokens: 0),
                webSearchCall: nil
            )
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesWebSearch.nonStreamingResponse(
                    prepared: prepared,
                    traces: [],
                    finalTurn: invalidTurn,
                    usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
                )
            }
        }

        let invalidPrepared = PreparedResponsesWebSearchRequest(
            upstreamBody: prepared.upstreamBody,
            originalBody: prepared.originalBody,
            originalModel: prepared.originalModel,
            originalToolsJSON: Data("{".utf8),
            originalInputJSON: prepared.originalInputJSON,
            streaming: false,
            maximumUses: prepared.maximumUses
        )
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesWebSearch.nonStreamingResponse(
                prepared: invalidPrepared,
                traces: [],
                finalTurn: try validationFinalTurn(output: []),
                usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
            )
        }
    }

    @Test("Streaming rejects unknown items and incomplete standard items")
    func streamingValidation() throws {
        let prepared = try validationPrepared(streaming: true)
        let unknown = try validationUnknownTurn()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesWebSearch.streamingResponse(
                prepared: prepared,
                traces: [],
                finalTurn: unknown,
                usage: ResponsesUsage(inputTokens: 1, outputTokens: 1)
            )
        }

        let missingTypeOutput: [[String: Any]] = [["id": "custom"]]
        let missingTypeRoot: [String: Any] = [
            "id": "resp_final",
            "object": "response",
            "status": "completed",
            "model": "target",
            "output": missingTypeOutput,
            "usage": [:],
        ]
        let missingType = ResponsesModelTurn(
            id: "resp_final",
            rootJSON: try JSONSerialization.data(withJSONObject: missingTypeRoot),
            outputJSON: try JSONSerialization.data(withJSONObject: missingTypeOutput),
            usage: ResponsesUsage(inputTokens: 0, outputTokens: 0),
            webSearchCall: nil
        )
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesWebSearch.streamingResponse(
                prepared: prepared,
                traces: [],
                finalTurn: missingType,
                usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
            )
        }

        let missingSummary = try validationFinalTurn(output: [["id": "rs", "type": "reasoning"]])
        let missingSummaryStream = try OpenAIResponsesWebSearch.streamingResponse(
            prepared: prepared,
            traces: [],
            finalTurn: missingSummary,
            usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
        )
        #expect(
            String(data: missingSummaryStream, encoding: .utf8)?
                .contains("response.output_item.done") == true
        )

        let invalidOutputs: [[[String: Any]]] = [
            [["id": "msg", "type": "message"]],
            [
                [
                    "id": "msg",
                    "type": "message",
                    "content": [["type": "output_text"]],
                ]
            ],
            [
                [
                    "type": "function_call",
                    "name": "weather",
                    "call_id": "call",
                    "arguments": "{}",
                ]
            ],
        ]
        for output in invalidOutputs {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesWebSearch.streamingResponse(
                    prepared: prepared,
                    traces: [],
                    finalTurn: try validationFinalTurn(output: output),
                    usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
                )
            }
        }
    }

    @Test("Streaming ignores invalid reasoning summaries but emits valid ones")
    func streamingReasoningValidation() throws {
        let prepared = try validationPrepared(streaming: true)
        let turn = try validationFinalTurn(
            output: [
                [
                    "id": "rs",
                    "type": "reasoning",
                    "summary": [
                        ["type": "unknown"],
                        ["type": "summary_text", "text": "valid"],
                    ],
                ]
            ]
        )
        let stream = try OpenAIResponsesWebSearch.streamingResponse(
            prepared: prepared,
            traces: [],
            finalTurn: turn,
            usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
        )
        let text = try #require(String(data: stream, encoding: .utf8))
        #expect(text.contains(#""delta":"valid""#))
    }
}

private func validationPrepared(
    streaming: Bool = false
) throws -> PreparedResponsesWebSearchRequest {
    let body = try JSONSerialization.data(
        withJSONObject: [
            "model": "slug",
            "input": "question",
            "stream": streaming,
            "tools": [["type": "web_search"]],
        ]
    )
    let candidate = try OpenAIResponsesWebSearch.prepare(
        body: body,
        targetModel: "target",
        configuration: .firecrawlCloud
    )
    return try #require(candidate)
}

private func validationSearchTurn() throws -> ResponsesModelTurn {
    try validationFinalTurn(output: [validationSearchItem()])
}

private func validationUnknownTurn() throws -> ResponsesModelTurn {
    try validationFinalTurn(output: [
        [
            "id": "custom",
            "type": "custom",
            "provider_secret": "provider-secret-unknown-item",
        ]
    ])
}

private func validationSearchItem() -> [String: Any] {
    [
        "id": "fc_search",
        "type": "function_call",
        "name": "web_search",
        "call_id": "call_search",
        "arguments": #"{"query":"Swift"}"#,
    ]
}

private func validationFinalTurn(
    output: [[String: Any]]
) throws -> ResponsesModelTurn {
    let body = try JSONSerialization.data(
        withJSONObject: [
            "id": "resp_final",
            "object": "response",
            "status": "completed",
            "model": "target",
            "output": output,
            "usage": [:],
        ]
    )
    return try OpenAIResponsesWebSearch.parseModelTurn(body)
}

private func validationObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite("OpenAI Responses web search engagement")
struct OpenAIResponsesWebSearchEngagementTests {
    @Test("An explicit external_web_access refusal keeps the bridge disengaged")
    func externalWebAccessRefusal() throws {
        // Codex pins the tool's reach with external_web_access when its own
        // search toggle is off; the native backend then never searches, so
        // the bridge must not offer its private tool either.
        let refused =
            #"{"model":"slug","input":"x","#
            + #""tools":[{"type":"web_search","external_web_access":false}]}"#
        #expect(
            try OpenAIResponsesWebSearch.prepare(
                body: Data(refused.utf8),
                targetModel: "target",
                configuration: .firecrawlCloud
            )?.maximumUses == 0
        )

        // Absent and explicitly allowed both engage, matching the native
        // default.
        for tool in [
            #"{"type":"web_search"}"#,
            #"{"type":"web_search","external_web_access":true}"#,
        ] {
            let body = #"{"model":"slug","input":"x","tools":[\#(tool)]}"#
            let prepared = try OpenAIResponsesWebSearch.prepare(
                body: Data(body.utf8),
                targetModel: "target",
                configuration: .firecrawlCloud
            )
            #expect(prepared != nil)
        }
    }
}
