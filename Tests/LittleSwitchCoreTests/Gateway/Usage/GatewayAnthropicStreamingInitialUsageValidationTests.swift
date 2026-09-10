import AsyncHTTPClient
import Foundation
import Hummingbird
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway Anthropic streaming initial usage validation")
struct GatewayStreamingInitialUsageTests {
    @Test("A message start without usage is rejected")
    func missingUsage() async throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        let message = try JSONSerialization.data(withJSONObject: [
            "id": "msg_missing_usage",
            "type": "message",
            "content": [],
        ])
        var session = AnthropicPublicStreamSession(originalModel: "original")
        var writer: any ResponseBodyWriter = CoverageThrowingWriter(failure: .none)

        await #expect(throws: GatewayAnthropicLiveError.invalidProviderResponse) {
            try await responder.publishAnthropicLiveEvent(
                .messageStart(messageJSON: message),
                session: &session,
                writer: &writer
            )
        }
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
