import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import NIOEmbedded
import Testing

@testable import LittleSwitchCore

@Suite("Native compaction recovery routing")
struct NativeCompactionRecoveryRouteTests {
    @Test("Opaque recovery completes before the admitted custom turn", arguments: [false, true])
    func recoversBeforeCustomTurn(hasTrigger: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        await fixture.state.responsesCapabilities.record(
            providerID: fixture.snapshot.providers[0].id, supportsNative: true)
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: Self.catalog),
            response(status: .ok, body: compactionSummaryResponse()),
            response(
                status: hasTrigger ? .ok : .accepted,
                body: hasTrigger ? compactionSummaryResponse() : Self.continuation),
        ])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)
        try await app.test(.router) { client in
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
                #expect(text.contains("opaque-native-checkpoint"))
                #expect(text.contains("native-setting-marker"))
            } else {
                #expect(text == Self.continuation)
            }
        }
        let requests = await transport.requests
        #expect(requests.count == 3)
        let discovery = try #require(requests.first)
        #expect(discovery.url == "https://api.openai.com/v1/models")
        #expect(discovery.headers["authorization"] == ["Bearer synthetic-openai"])
        let native = try #require(requests.dropFirst().first)
        #expect(native.url == "https://api.openai.com/v1/responses")
        #expect(native.headers["authorization"] == ["Bearer synthetic-openai"])
        let nativeBody = try responsesStreamObject(native.body)
        let nativeInput = try #require(nativeBody["input"] as? [[String: Any]])
        #expect(nativeInput.contains { $0["encrypted_content"] as? String == "opaque-native-checkpoint" })
        let custom = try #require(requests.last)
        #expect(custom.url.hasPrefix(fixture.snapshot.providers[0].baseURL))
        #expect(custom.headers["authorization"] == ["Bearer selected-secret"])
        let customBody = try responsesStreamObject(custom.body)
        #expect(customBody["model"] as? String == "glm-5.2")
        let customInput = try #require(customBody["input"] as? [[String: Any]])
        let inputText = try ResponsesCompactionJSON.text(customInput)
        #expect(inputText.contains("Continue the implementation; the file was read."))
        #expect(!inputText.contains("opaque-native-checkpoint"))
        #expect(!inputText.contains("native-setting-marker"))
        #expect(!inputText.contains("opaque-native-reasoning"))
        #expect(await fixture.state.codexSessionRequestCount == 1)
    }

    @Test("An opaque checkpoint without native authentication returns 401 before transport")
    func requiresAuthentication() async throws {
        let fixture = try GatewayTests().makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        try await GatewayTests().makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: request()))
            #expect(result.status == .unauthorized)
            #expect(String(buffer: result.body).contains(CodexNativePassthrough.sentinelRejectionMessage))
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Discovery and native summary errors retain their upstream status", arguments: [false, true])
    func preservesUpstreamFailure(duringSummary: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let responses =
            (duringSummary ? [response(status: .ok, body: Self.catalog)] : [])
            + [response(status: .tooManyRequests, body: "native rate limit")]
        let transport = RecordingGatewayTransport(responses: responses)
        try await GatewayTests().makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.authorization: "Bearer synthetic-openai"],
                body: ByteBuffer(bytes: request())
            )
            #expect(result.status == .tooManyRequests)
            #expect(String(buffer: result.body) == "native rate limit")
        }
        #expect(await transport.requests.count == (duringSummary ? 2 : 1))
    }

    @Test("An unusable native catalog returns 502 without a custom request")
    func rejectsInvalidDiscovery() async throws {
        let fixture = try GatewayTests().makeFixture()
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: #"{"data":[]}"#)])
        try await GatewayTests().makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.authorization: "Bearer synthetic-openai"],
                body: ByteBuffer(bytes: request())
            )
            #expect(result.status == .badGateway)
            #expect(String(buffer: result.body).contains("Could not recover the OpenAI conversation checkpoint"))
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("Recovery cancellation propagates through the routed responder")
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

    private static let catalog = #"{"data":[{"id":"gpt-5.6-sol"}]}"#
    private static let continuation =
        #"{"id":"resp_custom","status":"completed","output":[],"usage":{"input_tokens":1,"output_tokens":1}}"#

    private func request(hasTrigger: Bool = false) throws -> Data {
        let input: [[String: Any]] =
            [
                ["type": "compaction", "encrypted_content": "opaque-native-checkpoint"],
                [
                    "type": "configuration_update", "model": "native-setting-marker",
                    "reasoning_effort": "high",
                ],
                [
                    "type": "reasoning", "id": "rs_original", "summary": [],
                    "encrypted_content": "opaque-native-reasoning",
                ],
                ["type": "message", "role": "user", "content": "Continue the implementation."],
            ] + (hasTrigger ? [["type": "compaction_trigger"]] : [])
        return try ResponsesCompactionJSON.data([
            "model": "z.ai/glm-5.2", "stream": hasTrigger, "input": input,
        ])
    }
}
