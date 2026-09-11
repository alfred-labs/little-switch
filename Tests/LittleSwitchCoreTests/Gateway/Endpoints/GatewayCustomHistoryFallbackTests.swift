import Foundation
import HTTPTypes
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway custom history fallback")
struct GatewayCustomHistoryFallbackTests {
    @Test("Function-only egress preserves original freeform history for returning to OpenAI", arguments: [false, true])
    func providerReturn(chat: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        await fixture.state.responsesCapabilities.record(providerID: provider.id, supportsNative: !chat)
        let chatBody = try chatReasoningResponse(message: ["role": "assistant", "content": "Continued"])
        let nativeBody = try chatReasoningProjection(fields: [:])
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: try chatReasoningText(chat ? chatBody : nativeBody)),
            response(status: .accepted, body: "{}"),
        ])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)
        let original = try customHistoryFallbackRequest(model: "gpt-5.6-sol")
        try await app.test(.router) { client in
            let switched = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(bytes: try customHistoryFallbackRequest(model: "z.ai/glm-5.2"))
            )
            #expect(switched.status == .ok)
            let returned = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.authorization: "Bearer synthetic-openai"],
                body: ByteBuffer(bytes: original)
            )
            #expect(returned.status == .accepted)
        }
        let requests = await transport.requests
        #expect(requests.count == 2)
        let first = try #require(requests.first)
        let custom = try chatJSONObject(first.body)
        if chat {
            let messages = try #require(custom["messages"] as? [[String: Any]])
            let call = try #require((messages.first?["tool_calls"] as? [[String: Any]])?.first)
            #expect(call["type"] as? String == "function")
        } else {
            let input = try #require(custom["input"] as? [[String: Any]])
            #expect(input.first?["type"] as? String == "function_call")
            #expect(input[1]["type"] as? String == "function_call_output")
        }
        let returned = try #require(requests.last)
        #expect(returned.url == "https://api.openai.com/v1/responses")
        #expect(returned.body == original)
    }
}
