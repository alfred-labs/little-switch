import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("A provider can send low effort for disabled thinking while retaining the original client trace")
    func disabledThinkingLowEffort() async throws {
        let base = try makeFixture()
        let encodedProvider = try JSONEncoder().encode(#require(base.snapshot.providers.first))
        var providerObject = try #require(
            JSONSerialization.jsonObject(with: encodedProvider) as? [String: Any]
        )
        providerObject["disabledThinkingOverride"] = "lowEffort"
        let provider = try JSONDecoder().decode(
            Provider.self,
            from: JSONSerialization.data(withJSONObject: providerObject)
        )
        let snapshot = RoutingSnapshot(
            generation: base.snapshot.generation,
            providers: [provider],
            mappings: base.snapshot.mappings
        )
        let fixture = GatewayFixture(
            snapshot: snapshot,
            state: GatewayState(snapshot: snapshot),
            secrets: base.secrets
        )
        let providerResponse = #"{"type":"message","content":[{"type":"text","text":"ok"}]}"#
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: providerResponse)])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(fixture: fixture, transport: transport, trafficRecorder: recorder)
        let incoming = Data(
            #"""
            {"model":"claude-opus-5","thinking":{"type":"disabled","budget_tokens":1024},
             "max_tokens":2048,"output_config":{"format":{"type":"text"}},"stop_sequences":["stop"],
             "metadata":{"opaque":7},"messages":[{"role":"user","content":[
               {"type":"text","text":"hello","cache_control":{"type":"ephemeral"}}
             ]}]}
            """#.utf8
        )

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(bytes: incoming)
            )
            #expect(result.status == .ok)
            #expect(data(result.body) == Data(providerResponse.utf8))
        }

        let request = try #require(await transport.requests.first)
        var expected = try #require(JSONSerialization.jsonObject(with: incoming) as? [String: Any])
        expected["model"] = "glm-5.2"
        expected["output_config"] = ["format": ["type": "text"], "effort": "low"]
        let actual = try #require(JSONSerialization.jsonObject(with: request.body) as? NSDictionary)
        #expect(actual == expected as NSDictionary)
        let event = try #require(recorder.events.first)
        #expect(event.claudeRequest.body == incoming)
        #expect(event.upstreamExchanges.count == 1)
        #expect(event.upstreamExchanges.first?.request?.body == request.body)
        #expect(event.clientResponse.body == Data(providerResponse.utf8))
    }

    @Test(
        "Native 64-token requests retain their budget and streaming response bytes",
        arguments: [
            ProviderDisabledThinkingOverride.lowEffort,
            ProviderDisabledThinkingOverride.passthrough,
        ], [false, true]
    )
    func disabledThinkingNativeShape(
        override: ProviderDisabledThinkingOverride, streaming: Bool
    ) async throws {
        let fixture = try thinkingFixture(override: override)
        let responseBody = streaming ? "data: {\"type\":\"ping\"}\n\n" : #"{"type":"message","content":[]}"#
        let upstream =
            streaming
            ? streamingResponse(status: .ok, headers: ["content-type": "text/event-stream"], chunks: [responseBody])
            : response(status: .ok, body: responseBody)
        let transport = RecordingGatewayTransport(responses: [upstream])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(fixture: fixture, transport: transport, trafficRecorder: recorder)
        let incoming = Data(
            #"""
            {"model":"claude-opus-5","max_tokens":64,"thinking":{"type":"disabled"},
             "stream":\#(streaming),"messages":[{"role":"user","content":"Return a score."}]}
            """#.utf8
        )

        try await app.test(.router) { client in
            let result = try await client.execute(uri: "/v1/messages", method: .post, body: ByteBuffer(bytes: incoming))
            #expect(result.status == .ok)
            #expect(data(result.body) == Data(responseBody.utf8))

            let count = try await client.execute(
                uri: "/v1/messages/count_tokens", method: .post, body: ByteBuffer(bytes: incoming)
            )
            #expect(count.status == .ok)
            #expect(
                try JSONSerialization.jsonObject(with: data(count.body)) as? [String: Int]
                    == ["input_tokens": TokenEstimator.estimate(incoming)]
            )
        }

        let requests = await transport.requests
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        var expected = try #require(JSONSerialization.jsonObject(with: incoming) as? [String: Any])
        expected["model"] = "glm-5.2"
        if override == .lowEffort { expected["output_config"] = ["effort": "low"] }
        #expect(try JSONSerialization.jsonObject(with: request.body) as? NSDictionary == expected as NSDictionary)
        #expect(recorder.events.first?.claudeRequest.body == incoming)
        #expect(recorder.events.first?.upstreamExchanges.first?.request?.body == request.body)
        #expect(recorder.events.last?.claudeRequest.body == incoming)
        #expect(recorder.events.last?.upstreamExchanges.isEmpty == true)
    }

    @Test("Image fallback retains the chosen thinking effort on both attempts")
    func disabledThinkingImageRetry() async throws {
        let fixture = try thinkingFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .badRequest,
                body:
                    #"{"type":"error","error":{"type":"invalid_request_error","message":"This model does not support image input"}}"#
            ),
            response(status: .ok, body: #"{"type":"message","content":[]}"#),
        ])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(fixture: fixture, transport: transport, trafficRecorder: recorder)
        let incoming = Data(
            #"""
            {"model":"claude-opus-5","max_tokens":64,"thinking":{"type":"disabled"},
             "messages":[{"role":"user","content":[
               {"type":"image","source":{"type":"base64","data":"fixture-image"}},
               {"type":"text","text":"keep","cache_control":{"type":"ephemeral"}}
             ]}]}
            """#.utf8
        )

        try await app.test(.router) { client in
            let result = try await client.execute(uri: "/v1/messages", method: .post, body: ByteBuffer(bytes: incoming))
            #expect(result.status == .ok)
        }

        let requests = await transport.requests
        try #require(requests.count == 2)
        var expected = try #require(JSONSerialization.jsonObject(with: incoming) as? [String: Any])
        expected["model"] = "glm-5.2"
        expected["output_config"] = ["effort": "low"]
        #expect(try JSONSerialization.jsonObject(with: requests[0].body) as? NSDictionary == expected as NSDictionary)
        expected["messages"] = [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": ImageFallback.notice],
                    ["type": "text", "text": "keep", "cache_control": ["type": "ephemeral"]],
                ],
            ]
        ]
        #expect(try JSONSerialization.jsonObject(with: requests[1].body) as? NSDictionary == expected as NSDictionary)
        let event = try #require(recorder.events.first)
        #expect(event.claudeRequest.body == incoming)
        #expect(event.upstreamExchanges.compactMap { $0.request?.body } == requests.map(\.body))
        #expect(event.didRetryImages)
        #expect(await fixture.state.sessionRequestCount == 1)
    }

    func thinkingFixture(
        override: ProviderDisabledThinkingOverride = .lowEffort,
        webSearch: Bool = false
    ) throws -> GatewayFixture {
        let base = try webSearch ? makeWebSearchFixture(maximumUses: 1) : makeFixture()
        var snapshot = base.snapshot
        snapshot.providers[0].disabledThinkingOverride = override
        return GatewayFixture(snapshot: snapshot, state: GatewayState(snapshot: snapshot), secrets: base.secrets)
    }
}
