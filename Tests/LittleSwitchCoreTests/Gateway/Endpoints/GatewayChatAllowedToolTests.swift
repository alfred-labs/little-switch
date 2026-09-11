import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway allowed tool parity")
struct GatewayChatAllowedToolTests {
    @Test(
        "An excluded plain tool cannot be rewritten into a permitted namespace child", arguments: [false, true],
        [false, true])
    func excludedPlainIdentity(streaming: Bool, chat: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        await fixture.state.responsesCapabilities.record(providerID: provider.id, supportsNative: !chat)
        let chatResponse: [String: Any] = [
            "choices": [
                [
                    "finish_reason": "tool_calls",
                    "message": [
                        "tool_calls": [
                            [
                                "id": "call_excluded", "type": "function",
                                "function": ["name": "run", "arguments": "{}"],
                            ]
                        ]
                    ],
                ]
            ]
        ]
        let nativeResponse: [String: Any] = [
            "id": "resp_excluded", "status": "completed",
            "output": [
                [
                    "type": "function_call", "id": "fc_excluded", "call_id": "call_excluded", "name": "run",
                    "arguments": "{}",
                ]
            ],
        ]
        let providerBody = try chatJSONData(chat ? chatResponse : nativeResponse)
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: try chatReasoningText(providerBody))
        ])
        let body = try chatJSONData([
            "model": "z.ai/glm-5.2", "input": "Use the allowed tool", "stream": streaming,
            "tools": [
                ["type": "function", "name": "run"],
                ["type": "namespace", "name": "workspace", "tools": [["type": "function", "name": "run"]]],
            ],
            "tool_choice": [
                "type": "allowed_tools", "mode": "required",
                "tools": [["type": "function", "namespace": "workspace", "name": "run"]],
            ],
        ])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)
        try await app.test(.router) { client in
            let result = try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: body))
            #expect(result.status == .badGateway)
            let responseBody = try chatJSONObject(Data(result.body.readableBytesView))
            #expect(responseBody["error"] is [String: Any])
            #expect(responseBody["output"] == nil)
        }
        let upstream = try #require(await transport.requests.first)
        let request = try chatJSONObject(upstream.body)
        let tools = try #require(request["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        let definition = chat ? tools.first?["function"] as? [String: Any] : tools.first
        #expect(definition?["name"] as? String == "workspace__run")
        #expect(request["tool_choice"] as? String == "required")
    }
}
