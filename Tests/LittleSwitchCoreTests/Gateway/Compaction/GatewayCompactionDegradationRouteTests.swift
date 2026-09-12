import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import NIOEmbedded
import Testing

@testable import LittleSwitchCore

@Suite("Compaction degradation routing")
struct GatewayCompactionDegradationRouteTests {
    @Test("Foreign checkpoints degrade before the admitted turn without native exchanges", arguments: [false, true])
    func degradesBeforeAdmittedTurn(hasTrigger: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        await fixture.state.responsesCapabilities.record(
            providerID: fixture.snapshot.providers[0].id, supportsNative: true)
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: hasTrigger ? .ok : .accepted,
                body: hasTrigger ? compactionSummaryResponse() : Self.continuation)
        ])
        try await GatewayTests().makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.authorization: "Bearer synthetic-openai"],
                body: ByteBuffer(bytes: request(hasTrigger: hasTrigger))
            )
            #expect(result.status == (hasTrigger ? .ok : .accepted))
            let text = String(buffer: result.body)
            if hasTrigger {
                #expect(text.contains("little_switch_compaction"))
            } else {
                #expect(text == Self.continuation)
            }
        }
        // The Ollama posture: no discovery, no native summary turn — the only
        // upstream exchange is the admitted provider turn itself.
        let requests = await transport.requests
        #expect(requests.count == 1)
        let custom = try #require(requests.first)
        #expect(custom.url.hasPrefix(fixture.snapshot.providers[0].baseURL))
        #expect(custom.headers["authorization"] == ["Bearer selected-secret"])
        let customBody = try responsesStreamObject(custom.body)
        #expect(customBody["model"] as? String == "glm-5.2")
        let input = try #require(customBody["input"] as? [[String: Any]])
        let text = try ResponsesCompactionJSON.text(input)
        #expect(text.contains("Continue the implementation."))
        #expect(text.contains(ResponsesProviderState.degradationNotice))
        #expect(!text.contains("opaque-native-checkpoint"))
        #expect(!text.contains("native-setting-marker"))
        #expect(!text.contains("opaque-native-reasoning"))
    }

    @Test("A history even degradation cannot admit returns 400")
    func rejectsUnadmittableDegradation() async throws {
        let fixture = try GatewayTests().makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        try await GatewayTests().makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.authorization: "Bearer synthetic-openai"],
                body: ByteBuffer(bytes: try request(corruptTaggedReasoning: true))
            )
            #expect(result.status == .badRequest)
            #expect(String(buffer: result.body).contains("Invalid Responses request"))
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Degradation replaces only checkpoints no adapter can expand")
    func degradedBodyOnlyReplacesForeignCheckpoints() throws {
        let owned = try ResponsesCompactionFixture.owned(summary: "Portable.")
        let portable = try ResponsesCompactionJSON.data([
            "model": "z.ai/glm-5.2", "stream": false,
            "input": [owned, ["type": "message", "role": "user", "content": "Continue."]],
        ])
        #expect(try ResponsesProviderState.degradedBody(portable) == portable)
        let foreign = try ResponsesCompactionJSON.data([
            "model": "z.ai/glm-5.2", "stream": false,
            "input": [
                ["type": "compaction", "encrypted_content": "opaque-provider-ciphertext"],
                ["type": "message", "role": "user", "content": "Continue."],
            ],
        ])
        let degraded = try ResponsesProviderState.degradedBody(foreign)
        let input = try #require(try responsesStreamObject(degraded)["input"] as? [[String: Any]])
        #expect(try ResponsesCompactionJSON.text(input).contains(ResponsesProviderState.degradationNotice))
        #expect(input.allSatisfy { $0["type"] as? String != "compaction" })
    }

    @Test("Degradation cancellation propagates through the routed responder")
    func propagatesCancellation() async throws {
        let fixture = try GatewayTests().makeFixture()
        let transport = SteppingGatewayTransport(steps: [.cancellation])
        let recorder = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder
        )
        let incoming = Request(
            head: HTTPRequest(
                method: .post,
                scheme: "http",
                authority: "localhost",
                path: "/v1/responses",
                headerFields: [.authorization: "Bearer synthetic-openai"]
            ),
            body: RequestBody(buffer: ByteBuffer(bytes: try request()))
        )
        let channel = EmbeddedChannel()
        let context = BasicRequestContext(
            source: ApplicationRequestContextSource(channel: channel, logger: Logger(label: #function)))
        await #expect(throws: CancellationError.self) {
            _ = try await responder.respond(to: incoming, context: context)
        }
        _ = try channel.finish()
        #expect(await transport.requests.count == 1)
        #expect(recorder.events.map(\.lifecycle) == [.cancelled])
        #expect(recorder.events.allSatisfy { $0.finalStatus == nil })
    }

    private static let continuation =
        #"{"id":"resp_custom","status":"completed","output":[],"usage":{"input_tokens":1,"output_tokens":1}}"#

    private func request(hasTrigger: Bool = false, corruptTaggedReasoning: Bool = false) throws -> Data {
        let reasoning: [String: Any]
        if corruptTaggedReasoning {
            reasoning = [
                "type": "reasoning", "id": "rs_corrupt", "summary": [],
                "encrypted_content": try ResponsesCompactionJSON.text([
                    "type": "little_switch_reasoning", "version": 2,
                    "provider_id": "not-a-uuid", "item": ["type": "reasoning"],
                ]),
            ]
        } else {
            reasoning = [
                "type": "reasoning", "id": "rs_original", "summary": [],
                "encrypted_content": "opaque-native-reasoning",
            ]
        }
        let input: [[String: Any]] =
            [
                ["type": "compaction", "encrypted_content": "opaque-native-checkpoint"],
                [
                    "type": "configuration_update", "model": "native-setting-marker",
                    "reasoning_effort": "high",
                ],
                reasoning,
                ["type": "message", "role": "user", "content": "Continue the implementation."],
            ] + (hasTrigger ? [["type": "compaction_trigger"]] : [])
        return try ResponsesCompactionJSON.data([
            "model": "z.ai/glm-5.2", "stream": hasTrigger, "input": input,
        ])
    }
}
