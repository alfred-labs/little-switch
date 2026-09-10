import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway web-search initial usage")
struct GatewayWebSearchInitialUsageTests {
    @Test("A zero first provider turn normalizes the one public start only")
    func zeroFirstTurnNormalizesPublicStart() async throws {
        let fixture = try GatewayTests().makeWebSearchFixture()
        let providerFrames = try terminalFrames(id: "zero_first", inputTokens: 0)
        let transport = RecordingGatewayTransport(responses: [
            gatewayStreamingResponse(
                GatewayGatedBody(chunks: [try gatewayProviderSSE(providerFrames)])
            )
        ])
        let resolver = WebSearchInitialUsageResolverProbe(
            mode: .fixed(.providerEstimate(tokens: 17, elapsedMilliseconds: 6))
        )
        let recorder = TrafficTestRecorder()
        let responder = makeResponder(
            fixture: fixture,
            transport: transport,
            resolver: resolver,
            recorder: recorder
        )
        let context = try GatewayTests().gatewayLiveContext(fixture: fixture)

        let response = try await responder.webSearchResponse(context: context)
        let events = try publicEvents(try await responseBodyData(response.body))

        let start = try #require(events.first { $0.name == "message_start" })
        let message = try #require(start.payload["message"] as? [String: Any])
        let startUsage = try #require(message["usage"] as? [String: Any])
        #expect(startUsage["input_tokens"] as? Int == 17)

        let terminal = try #require(events.last { $0.name == "message_delta" })
        let terminalUsage = try #require(terminal.payload["usage"] as? [String: Any])
        #expect(terminalUsage["input_tokens"] as? Int == 0)
        #expect(events.filter { $0.name == "message_start" }.count == 1)
        #expect(await resolver.callCount == 1)
        #expect(await resolver.requests.first?.upstreamBody == context.prepared.upstreamBody)
        #expect(
            recorder.events.first?.initialUsageEstimate
                == TrafficInitialUsageEstimate(
                    tokenCount: 17,
                    source: .provider,
                    providerOutcome: .success,
                    elapsedMilliseconds: 6
                )
        )
    }

    @Test("A later internal zero turn never triggers counting after a native public start")
    func laterInternalTurnNeverCounts() async throws {
        let fixture = try GatewayTests().makeWebSearchFixture()
        let first = try gatewayProviderSSE(searchedProviderTurnFrames())
        let final = try gatewayProviderSSE(
            terminalFrames(id: "zero_internal", inputTokens: 0)
        )
        let transport = RecordingGatewayTransport(responses: [
            gatewayStreamingResponse(GatewayGatedBody(chunks: [first])),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            gatewayStreamingResponse(GatewayGatedBody(chunks: [final])),
        ])
        let resolver = WebSearchInitialUsageResolverProbe(mode: .forbidden)
        let responder = makeResponder(
            fixture: fixture,
            transport: transport,
            resolver: resolver,
            recorder: TrafficTestRecorder()
        )

        let response = try await responder.webSearchResponse(
            context: GatewayTests().gatewayLiveContext(fixture: fixture)
        )
        let events = try publicEvents(try await responseBodyData(response.body))

        let start = try #require(events.first { $0.name == "message_start" })
        let message = try #require(start.payload["message"] as? [String: Any])
        let usage = try #require(message["usage"] as? [String: Any])
        #expect(usage["input_tokens"] as? Int == 12)
        #expect(events.filter { $0.name == "message_start" }.count == 1)
        #expect(await resolver.callCount == 0)
        #expect(await transport.requests.count == 3)
    }

    @Test("A zero JSON fallback turn uses the same first-start resolver")
    func zeroJSONFallbackUsesResolver() async throws {
        let fixture = try GatewayTests().makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "json_zero",
                    content: [["type": "text", "text": "JSON"]],
                    stopReason: "end_turn",
                    inputTokens: 0,
                    outputTokens: 2
                )
            )
        ])
        let resolver = WebSearchInitialUsageResolverProbe(
            mode: .fixed(
                .localEstimate(
                    tokens: 11,
                    providerOutcome: .invalid,
                    elapsedMilliseconds: 1
                )
            )
        )
        let recorder = TrafficTestRecorder()
        let responder = makeResponder(
            fixture: fixture,
            transport: transport,
            resolver: resolver,
            recorder: recorder
        )

        let response = try await responder.webSearchResponse(
            context: GatewayTests().gatewayLiveContext(fixture: fixture)
        )
        let events = try publicEvents(try await responseBodyData(response.body))

        let start = try #require(events.first { $0.name == "message_start" })
        let message = try #require(start.payload["message"] as? [String: Any])
        let usage = try #require(message["usage"] as? [String: Any])
        #expect(usage["input_tokens"] as? Int == 11)
        #expect(await resolver.callCount == 1)
        #expect(
            recorder.events.first?.initialUsageEstimate
                == TrafficInitialUsageEstimate(
                    tokenCount: 11,
                    source: .localDividedByFour,
                    providerOutcome: .invalid,
                    elapsedMilliseconds: 1
                )
        )
    }

    private func terminalFrames(
        id: String,
        inputTokens: Int
    ) throws -> [ServerSentEventFrame] {
        [
            try providerFrame(
                "message_start",
                [
                    "type": "message_start",
                    "message": providerMessage(id: id, inputTokens: inputTokens),
                ]
            ),
            try providerFrame(
                "content_block_start",
                [
                    "type": "content_block_start",
                    "index": 0,
                    "content_block": ["type": "text", "text": ""],
                ]
            ),
            try providerFrame(
                "content_block_delta",
                [
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": ["type": "text_delta", "text": "Done"],
                ]
            ),
            try providerFrame(
                "content_block_stop",
                ["type": "content_block_stop", "index": 0]
            ),
            try providerFrame(
                "message_delta",
                [
                    "type": "message_delta",
                    "delta": ["stop_reason": "end_turn", "stop_sequence": NSNull()],
                    "usage": ["output_tokens": 2],
                ]
            ),
            try providerFrame("message_stop", ["type": "message_stop"]),
        ]
    }

    private func publicEvents(_ data: Data) throws -> [WebSearchPublicEvent] {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: max(data.count, 1))
        var frames = try decoder.append(ByteBuffer(bytes: data))
        frames += try decoder.finish()
        return try frames.map { frame in
            WebSearchPublicEvent(
                name: try #require(frame.event),
                payload: try #require(
                    JSONSerialization.jsonObject(with: frame.data) as? [String: Any]
                )
            )
        }
    }

    private func makeResponder(
        fixture: GatewayFixture,
        transport: any UpstreamTransport,
        resolver: any AnthropicInitialUsageResolving,
        recorder: any TrafficRecording
    ) -> GatewayResponder {
        GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder,
            dependencies: GatewayResponderDependencies(initialUsageResolver: resolver)
        )
    }
}

private struct WebSearchPublicEvent {
    let name: String
    let payload: [String: Any]
}

private actor WebSearchInitialUsageResolverProbe: AnthropicInitialUsageResolving {
    enum Mode: Sendable {
        case fixed(AnthropicInitialUsageResolution)
        case forbidden
    }

    private let mode: Mode
    private(set) var requests: [AnthropicInitialUsageRequestContext] = []

    init(mode: Mode) {
        self.mode = mode
    }

    var callCount: Int { requests.count }

    func estimate(
        request: AnthropicInitialUsageRequestContext,
        transport: any UpstreamTransport
    ) async throws -> AnthropicInitialUsageResolution {
        _ = transport
        requests.append(request)
        switch mode {
        case .fixed(let resolution):
            return resolution
        case .forbidden:
            throw GatewayTestError.failure
        }
    }
}
