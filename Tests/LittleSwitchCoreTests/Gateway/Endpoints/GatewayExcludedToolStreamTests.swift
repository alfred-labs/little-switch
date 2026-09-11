import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway excluded tool stream parity")
struct GatewayExcludedToolStreamTests {
    @Test("A rejected live call never exposes an executable item or its input", arguments: [false, true])
    func excludedCall(chat: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        await fixture.state.responsesCapabilities.record(providerID: provider.id, supportsNative: !chat)
        let transport = RecordingGatewayTransport(responses: [
            try streamingResponse(
                status: .ok, headers: ["content-type": "text/event-stream"], chunks: chunks(chat: chat))
        ])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)
        let body = try chatJSONData([
            "model": "z.ai/glm-5.2", "input": "Use the allowed tool", "stream": true,
            "tools": [
                ["type": "function", "name": "run"],
                ["type": "namespace", "name": "workspace", "tools": [["type": "function", "name": "run"]]],
            ],
            "tool_choice": [
                "type": "allowed_tools", "mode": "required",
                "tools": [["type": "function", "namespace": "workspace", "name": "run"]],
            ],
        ])
        try await app.test(.router) { client in
            let result = try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: body))
            let data = Data(result.body.readableBytesView)
            let text = try chatReasoningText(data)
            #expect(!text.contains("call_excluded"))
            #expect(!text.contains("SYNTHETIC_EXCLUDED_INPUT"))
            if result.status == .ok {
                let events = try ResponsesStreamingTestSupport.events(data)
                #expect(events.contains { $0.name == "error" })
                #expect(!events.contains { $0.name == "response.output_item.added" })
                #expect(!events.contains { $0.name == "response.function_call_arguments.delta" })
            } else {
                #expect(result.status == .badGateway)
                #expect(try chatJSONObject(data)["error"] is [String: Any])
            }
        }
    }

    private func chunks(chat: Bool) throws -> [String] {
        let arguments = "{\"value\":\"SYNTHETIC_EXCLUDED_INPUT\"}"
        if chat {
            let frames = try [
                chatChunkFrame(choices: [
                    chatChoice(delta: [
                        "tool_calls": [chatToolDelta(index: 0, id: "call_excluded", name: "run", arguments: arguments)]
                    ])
                ]),
                chatChunkFrame(
                    choices: [chatChoice(delta: [:], finishReason: "tool_calls")],
                    usage: ["prompt_tokens": 0, "completion_tokens": 0]),
                chatDoneFrame(),
            ]
            return try chatSSEChunks(frames).map(chatReasoningText)
        }
        let response: [String: Any] = [
            "id": "resp_excluded", "object": "response", "model": "glm-5.2", "status": "completed",
            "output": [
                [
                    "type": "function_call", "id": "fc_excluded", "call_id": "call_excluded", "name": "run",
                    "arguments": arguments, "status": "completed",
                ]
            ],
        ]
        return [try chatReasoningText(OpenAIResponsesStreaming.encode(completed: response))]
    }
}
