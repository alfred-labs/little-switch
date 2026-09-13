import AsyncHTTPClient
import Foundation
import Hummingbird
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway Anthropic streaming initial usage validation")
struct GatewayStreamingInitialUsageTests {
    @Test("A message start with missing or null usage is rejected", arguments: [false, true])
    func missingOrNullUsage(explicitNull: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        var fields: [String: Any] = [
            "id": "msg_missing_usage",
            "type": "message",
            "content": [],
        ]
        if explicitNull { fields["usage"] = NSNull() }
        let message = try JSONSerialization.data(withJSONObject: fields)
        var session = AnthropicPublicStreamSession(originalModel: "original")
        var writer: any ResponseBodyWriter = CoverageThrowingWriter(failure: .none)

        await #expect(throws: GatewayAnthropicLiveError.invalidProviderResponse) {
            try await responder.publishAnthropicLiveEvent(
                .messageStart(messageJSON: message),
                session: &session,
                writer: &writer
            )
        }
        #expect(!session.started)
    }

    @Test("An absent or null input counter is resolved before public start", arguments: [false, true])
    func unspecifiedInputCountUsesTheResolver(explicitNull: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        let resolver = GatewayInitialUsageResolverProbe(mode: .fixed(.native(17)))
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            dependencies: GatewayResponderDependencies(initialUsageResolver: resolver)
        )
        let request = AnthropicInitialUsageRequestContext(
            provider: provider,
            secret: nil,
            incomingHeaders: [:],
            upstreamBody: Data(#"{"model":"m","messages":[]}"#.utf8)
        )
        let message = Data(
            (explicitNull
                ? #"{"id":"msg_estimate","content":[],"usage":{"input_tokens":null,"output_tokens":0}}"#
                : #"{"id":"msg_estimate","content":[],"usage":{"output_tokens":0}}"#).utf8)
        var session = AnthropicPublicStreamSession(originalModel: "original")
        let recorder = StreamingStageRecorder()
        var writer: any ResponseBodyWriter = ObservingResponseBodyWriter(recorder: recorder)

        try await responder.publishAnthropicLiveEvent(
            .messageStart(messageJSON: message), session: &session, writer: &writer, initialUsageRequest: request
        )

        var decoder = ServerSentEventDecoder(maximumFrameBytes: 4_096)
        var frames = try decoder.append(ByteBuffer(bytes: await recorder.body))
        frames += try decoder.finish()
        #expect(frames.count == 1)
        let start = try #require(frames.first)
        #expect(start.event == "message_start")
        let published = try #require(JSONValue.parse(start.data).object?["message"]?.object)
        #expect(published["model"] == .string("original"))
        #expect(
            published["usage"]
                == (try JSONValue.parse(
                    #"""
                    {"input_tokens":17,"output_tokens":0,"cache_creation_input_tokens":0,
                     "cache_read_input_tokens":0,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},
                     "service_tier":null,"server_tool_use":{"web_fetch_requests":0,"web_search_requests":0}}
                    """#)))
    }

    @Test("A negative resolved usage count is rejected")
    func negativeResolvedUsage() async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            dependencies: GatewayResponderDependencies(
                initialUsageResolver: NegativeInitialUsageResolver()
            )
        )
        let message = try JSONSerialization.data(
            withJSONObject: providerMessage(id: "msg_negative_usage", inputTokens: 0)
        )
        let request = AnthropicInitialUsageRequestContext(
            provider: provider,
            secret: nil,
            incomingHeaders: [:],
            upstreamBody: Data("{}".utf8)
        )
        var session = AnthropicPublicStreamSession(originalModel: "original")
        var writer: any ResponseBodyWriter = CoverageThrowingWriter(failure: .none)

        await #expect(throws: GatewayAnthropicLiveError.invalidProviderResponse) {
            try await responder.publishAnthropicLiveEvent(
                .messageStart(messageJSON: message),
                session: &session,
                writer: &writer,
                initialUsageRequest: request
            )
        }
    }
}

private struct NegativeInitialUsageResolver: AnthropicInitialUsageResolving {
    func estimate(
        request: AnthropicInitialUsageRequestContext,
        transport: any UpstreamTransport
    ) async throws -> AnthropicInitialUsageResolution {
        _ = request
        _ = transport
        return .native(-1)
    }
}
