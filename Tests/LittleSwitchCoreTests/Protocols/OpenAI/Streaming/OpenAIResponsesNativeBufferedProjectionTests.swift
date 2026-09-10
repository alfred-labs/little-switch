import Foundation
import Testing

@testable import LittleSwitchCore

// The buffered half of the native namespace restoration suite: a non-
// streaming provider turn whose flattened call projects back as the
// `name` + `namespace` pair Codex resolves against.

extension OpenAIResponsesNativeStreamingTests {
    @Test("A buffered native projection restores the flattened call pair")
    func bufferedProjectionRestoresPair() throws {
        let bindings = [
            "collaboration__spawn_agent": ResponsesToolNamespaces.Binding(
                namespace: "collaboration",
                name: "spawn_agent"
            )
        ]
        let prepared = PreparedResponsesWebSearchRequest(
            upstreamBody: Data(),
            originalBody: try responseData(["model": "little-switch-route"]),
            originalModel: "little-switch-route",
            originalToolsJSON: try responseData([
                [
                    "type": "namespace",
                    "name": "collaboration",
                    "tools": [
                        [
                            "type": "function",
                            "name": "spawn_agent",
                            "parameters": ["type": "object", "properties": [:]],
                        ]
                    ],
                ]
            ]),
            originalInputJSON: Data("[]".utf8),
            streaming: false,
            maximumUses: 3,
            toolBindings: bindings
        )
        let finalTurnBody = try responseData([
            "id": "resp_buffered",
            "object": "response",
            "status": "completed",
            "model": "provider-model",
            "output": [
                [
                    "id": "fc_spawn",
                    "type": "function_call",
                    "status": "completed",
                    "call_id": "call_spawn",
                    "name": "collaboration__spawn_agent",
                    "arguments": #"{"message":"Go"}"#,
                ]
            ],
            "usage": [:],
        ])
        let finalTurn = try OpenAIResponsesWebSearch.parseModelTurn(finalTurnBody)

        let projected = try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: prepared,
            traces: [],
            finalTurn: finalTurn,
            usage: ResponsesUsage(inputTokens: 4, outputTokens: 2)
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: projected) as? [String: Any]
        )
        let output = try #require(object["output"] as? [[String: Any]])
        let call = try #require(output.first { $0["type"] as? String == "function_call" })
        #expect(call["name"] as? String == "spawn_agent")
        #expect(call["namespace"] as? String == "collaboration")
    }
}
