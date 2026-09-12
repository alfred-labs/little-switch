import Foundation
import HTTPTypes
import HummingbirdTesting
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("A missing Chat compaction route relearns Responses for the next request", arguments: [404, 405])
    func compactionRelearnsNativeRoute(status: Int) async throws {
        let fixture = try makeFixture()
        let providerID = fixture.snapshot.providers[0].id
        await fixture.state.responsesCapabilities.record(providerID: providerID, supportsNative: false)
        let transport = RecordingGatewayTransport(responses: [
            response(status: HTTPResponseStatus(statusCode: status), body: "Route missing"),
            response(status: .ok, body: compactionSummaryResponse()),
        ])
        let body = try compactionRequest(model: "z.ai/glm-5.2")
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let missing = try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: body))
            #expect(missing.status.code == status)
            #expect(String(buffer: missing.body) == "Route missing")
            #expect(await fixture.state.responsesCapabilities.verdict(for: providerID) == true)
            let retried = try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: body))
            #expect(retried.status == .ok)
            #expect(String(buffer: retried.body).contains("little_switch_compaction"))
        }
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.first?.url.hasSuffix("/chat/completions") == true)
        #expect(requests.last?.url.hasSuffix("/responses") == true)
    }

    @Test("Managed image compaction receives the ordinary Responses image compatibility", arguments: [false, true])
    func compactionImageCompatibility(native: Bool) async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: compactionSummaryResponse())])
        let body = try responsesStreamData([
            "model": native ? "gpt-native" : "z.ai/glm-5.2", "stream": true,
            "reasoning": ["effort": "max", "summary": "detailed"],
            "input": [
                [
                    "type": "message", "role": "user",
                    "content": [
                        ["type": "input_text", "text": "Preserve the screenshot findings."],
                        ["type": "input_image", "image_url": "data:image/png;base64,iVBORw0KGgo="],
                    ],
                ],
                ["type": "compaction_trigger"],
            ],
        ])
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: body))
            #expect(result.status == .ok)
        }
        let requests = await transport.requests
        #expect(requests.count == 1)
        let sent = try responsesStreamObject(try #require(requests.first).body)
        // The internal summary turn never carries reasoning configuration and
        // names its own bounded budget only where providers accept it: the
        // native chatgpt.com backend rejects the parameter outright.
        #expect(sent["reasoning"] == nil)
        #expect(sent["max_output_tokens"] as? Int == (native ? nil : 4_000))
        let input = try #require(sent["input"] as? [[String: Any]])
        let parts = input.compactMap { $0["content"] as? [[String: Any]] }.joined()
        #expect(parts.contains { $0["type"] as? String == "input_image" })
    }
}
