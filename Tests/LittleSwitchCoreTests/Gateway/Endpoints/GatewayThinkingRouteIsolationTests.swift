import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test(
        "The thinking override leaves Responses and chat-completions adaptation unchanged",
        arguments: [ProviderResponsesWireOverride.native, .chatCompletions]
    )
    func disabledThinkingRouteIsolation(wire: ProviderResponsesWireOverride) async throws {
        let base = try thinkingFixture(override: .passthrough)
        let mapping = try #require(base.snapshot.codex.resolvedDefaultModel(in: base.snapshot.providers))
        let slug = CodexCatalog.slug(for: mapping, in: base.snapshot.providers)
        let incoming = Data(
            #"""
            {"model":"\#(slug)","input":"hello","max_output_tokens":64,
             "thinking":{"type":"disabled"},"metadata":{"opaque":7}}
            """#.utf8
        )
        let providerResponse =
            wire == .native
            ? responsesModelResponse(id: "response_1", output: [])
            : #"{"id":"chatcmpl_1","created":1,"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}"#
        var upstreamBodies: [Data] = []

        for override in [
            ProviderDisabledThinkingOverride.passthrough,
            ProviderDisabledThinkingOverride.lowEffort,
        ] {
            var snapshot = base.snapshot
            snapshot.providers[0].disabledThinkingOverride = override
            snapshot.providers[0].responsesWireOverride = wire
            let fixture = GatewayFixture(
                snapshot: snapshot, state: GatewayState(snapshot: snapshot), secrets: base.secrets)
            let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: providerResponse)])
            let app = makeApplication(fixture: fixture, transport: transport)
            try await app.test(.router) { client in
                let result = try await client.execute(
                    uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: incoming))
                #expect(result.status == .ok)
            }
            let requests = await transport.requests
            #expect(requests.count == 1)
            let request = try #require(requests.first)
            let endpoint = wire == .native ? "/responses" : "/chat/completions"
            #expect(request.url.hasSuffix(endpoint))
            let object = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            #expect(object["output_config"] == nil)
            upstreamBodies.append(request.body)
        }

        #expect(upstreamBodies[0] == upstreamBodies[1])
    }
}
