import Foundation
import HTTPTypes
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway Chat reasoning parity")
struct GatewayChatReasoningParityTests {
    @Test(
        "Projected Chat state is durable, provider tagged, and excluded from native wires",
        arguments: ["json", "sse", "json-to-sse"])
    func durableProviderReasoning(mode: String) async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        await fixture.state.responsesCapabilities.record(providerID: provider.id, supportsNative: false)
        let fields = chatReasoningFields()
        var message: [String: Any] = ["role": "assistant", "content": "Visible answer"]
        for (key, value) in fields { message[key] = value }
        let chatBody = try chatReasoningResponse(message: message)
        let chatText = try chatReasoningText(chatBody)
        let transport = RecordingGatewayTransport(responses: [
            mode == "sse"
                ? try streamingResponse(
                    status: .ok,
                    headers: ["content-type": "text/event-stream"],
                    chunks: chatSSEChunks(chatReasoningFrames(fields: fields)).map {
                        try chatReasoningText($0)
                    }
                )
                : response(status: .ok, body: chatText),
            response(status: .accepted, body: "{}"),
            response(status: .ok, body: chatText),
            response(status: .accepted, body: "{}"),
        ])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)
        try await app.test(.router) { client in
            let first = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(
                    bytes: try chatJSONData([
                        "model": "z.ai/glm-5.2", "input": "Hello", "stream": mode != "json",
                    ]))
            )
            #expect(first.status == .ok)
            let projected: [String: Any]
            if mode == "json" {
                projected = try chatJSONObject(data(first.body))
            } else {
                let events = try ResponsesStreamingTestSupport.events(data(first.body))
                projected = try #require(events.last?.payload["response"] as? [String: Any])
                let doneItems = events.filter { $0.name == "response.output_item.done" }.compactMap {
                    $0.payload["item"] as? [String: Any]
                }
                let streamedReasoning = try #require(doneItems.first { $0["type"] as? String == "reasoning" })
                try expectProviderTag(streamedReasoning, providerID: provider.id)
            }
            let output = try #require(projected["output"] as? [[String: Any]])
            let reasoning = try #require(output.first { $0["type"] as? String == "reasoning" })
            try expectProviderTag(reasoning, providerID: provider.id)
            let history = try chatReasoningHistory(output, model: "z.ai/glm-5.2")

            await fixture.state.responsesCapabilities.record(providerID: provider.id, supportsNative: true)
            let sameProviderNative = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: history)
            )
            #expect(sameProviderNative.status == .accepted)
            await fixture.state.responsesCapabilities.record(providerID: provider.id, supportsNative: false)
            let restoredChat = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: history)
            )
            #expect(restoredChat.status == .ok)
            let native = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.authorization: "Bearer synthetic-openai"],
                body: ByteBuffer(bytes: try chatReasoningHistory(output, model: "gpt-5.6-sol"))
            )
            #expect(native.status == .accepted)
        }
        let requests = await transport.requests
        #expect(requests.count == 4)
        let sameProviderNative = try #require(requests.dropFirst().first)
        #expect(sameProviderNative.url.hasSuffix("/responses"))
        for request in [sameProviderNative, try #require(requests.last)] {
            let input = try #require(chatJSONObject(request.body)["input"] as? [[String: Any]])
            #expect(input.compactMap { $0["type"] as? String } == ["message", "message"])
            #expect(try !chatReasoningText(request.body).contains("little_switch_chat_reasoning"))
        }
        let restoredChat = try #require(requests.dropFirst(2).first)
        #expect(restoredChat.url.hasSuffix("/chat/completions"))
        let expected: [[String: Any]] = [message, ["role": "user", "content": "Continue"]]
        #expect(try chatJSONData(chatReasoningMessages(restoredChat.body)) == chatJSONData(expected))
    }

    private func expectProviderTag(_ item: [String: Any], providerID: UUID) throws {
        let encrypted = try #require(item["encrypted_content"] as? String)
        let payload = try chatJSONObject(Data(encrypted.utf8))
        #expect(payload["type"] as? String == "little_switch_reasoning")
        #expect(payload["version"] as? Int == 1)
        #expect(payload["provider_id"] as? String == providerID.uuidString)
        #expect((item["summary"] as? [Any])?.isEmpty == true)
    }
}
