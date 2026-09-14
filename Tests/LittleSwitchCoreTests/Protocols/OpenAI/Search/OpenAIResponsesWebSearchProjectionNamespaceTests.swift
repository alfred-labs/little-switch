import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses web search projection namespace restoration")
struct WebSearchProjectionNamespaceTests {
    /// The projection must resolve a provider near-miss against the
    /// request's own declared children and fail closed on malformed names.
    @Test("Projection restores a near-miss call and fails closed on malformed names")
    func projectionNamespaceRestoration() throws {
        var prepared = try bridgePrepared()
        let bindings: [String: ResponsesToolNamespaces.Binding] = [
            "collaboration__spawn_agent":
                ResponsesToolNamespaces.Binding(namespace: "collaboration", name: "spawn_agent")
        ]
        prepared.toolBindings = bindings
        prepared.declaredToolBindings = bindings
        let turn = try modelTurn(output: [
            [
                "id": "fc_nm",
                "type": "function_call",
                "name": "spawn_agent",
                "call_id": "call_nm",
                "arguments": "{}",
            ],
            [
                "id": "fc_unknown",
                "type": "function_call",
                "name": "totally_unknown",
                "call_id": "call_unknown",
                "arguments": "{}",
            ],
        ])
        let projected = try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: prepared,
            traces: [],
            finalTurn: turn,
            usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: projected) as? [String: Any]
        )
        let output = try #require(object["output"] as? [[String: Any]])
        let restored = try #require(output.first { $0["call_id"] as? String == "call_nm" })
        #expect(restored["name"] as? String == "spawn_agent")
        #expect(restored["namespace"] as? String == "collaboration")
        let unknown = try #require(output.first { $0["call_id"] as? String == "call_unknown" })
        #expect(unknown["name"] as? String == "totally_unknown")
        #expect(unknown["namespace"] == nil)

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            let malformedTurn = try modelTurn(output: [
                [
                    "id": "fc_bad",
                    "type": "function_call",
                    "name": 5,
                    "call_id": "call_bad",
                    "arguments": "{}",
                ]
            ])
            _ = try OpenAIResponsesWebSearch.nonStreamingResponse(
                prepared: prepared,
                traces: [],
                finalTurn: malformedTurn,
                usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
            )
        }
    }

    private func bridgePrepared() throws -> PreparedResponsesWebSearchRequest {
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "slug",
            "input": "question",
            "stream": false,
            "tools": [["type": "web_search"]],
        ])
        return try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: body,
                targetModel: "target",
                configuration: .firecrawlCloud
            )
        )
    }

    private func modelTurn(output: [[String: Any]]) throws -> ResponsesModelTurn {
        let body = try JSONSerialization.data(withJSONObject: [
            "id": "resp_final",
            "object": "response",
            "status": "completed",
            "model": "target",
            "output": output,
            "usage": [:],
        ])
        return try OpenAIResponsesWebSearch.parseModelTurn(body)
    }
}
