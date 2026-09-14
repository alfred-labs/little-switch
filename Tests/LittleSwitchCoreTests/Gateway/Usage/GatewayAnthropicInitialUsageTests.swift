import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Gateway Anthropic initial usage")
// swiftlint:disable:next type_body_length
struct GatewayAnthropicInitialUsageTests {
    @Test("Positive example usage stays byte-exact and never invokes the resolver")
    func nativeUsageIsExactPassthrough() async throws {
        let fixture = try GatewayTests().makeFixture()
        let wire = nativeWire
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream; charset=utf-8"],
                chunks: irregularChunks(of: wire)
            )
        ])
        let resolver = GatewayInitialUsageResolverProbe(mode: .forbidden)
        let recorder = TrafficTestRecorder()
        let app = application(
            fixture: fixture,
            transport: transport,
            resolver: resolver,
            recorder: recorder
        )

        let clientBody = try await executeStreamingRequest(app: app)

        #expect(clientBody == wire)
        #expect(await transport.requests.count == 1)
        #expect(await resolver.callCount == 0)
        let event = try #require(recorder.events.first)
        #expect(event.initialUsageEstimate == nil)
        #expect(event.upstreamExchanges.first?.response.body == wire)
        #expect(event.clientResponse.body == wire)
    }

    @Test("A zero z.ai start uses one provider estimate while terminal usage stays exact")
    func providerEstimateRewritesOnlyStart() async throws {
        let fixture = try GatewayTests().makeFixture()
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                chunks: irregularChunks(of: zeroWire)
            )
        ])
        let resolver = GatewayInitialUsageResolverProbe(
            mode: .fixed(.providerEstimate(tokens: 9, elapsedMilliseconds: 18))
        )
        let recorder = TrafficTestRecorder()
        let app = application(
            fixture: fixture,
            transport: transport,
            resolver: resolver,
            recorder: recorder
        )

        let clientBody = try await executeStreamingRequest(app: app)
        let clientText = try #require(String(data: clientBody, encoding: .utf8))

        #expect(clientText.contains(#""input_tokens":9"#))
        #expect(!clientText.contains(#""input_tokens":0"#))
        #expect(clientBody.suffix(terminalFrame.count) == terminalFrame)
        #expect(occurrences(of: terminalFrame, in: clientBody) == 1)
        #expect(await resolver.callCount == 1)
        #expect(await transport.requests.count == 1)

        let event = try #require(recorder.events.first)
        #expect(event.upstreamExchanges.first?.response.body == zeroWire)
        #expect(event.clientResponse.body == clientBody)
        #expect(
            event.initialUsageEstimate
                == TrafficInitialUsageEstimate(
                    tokenCount: 9,
                    source: .provider,
                    providerOutcome: .success,
                    elapsedMilliseconds: 18
                )
        )
    }

    @Test("Local fallback uses the exact semantic divided-by-four estimator result")
    func localFallbackUsesSharedEstimate() async throws {
        let fixture = try GatewayTests().makeFixture()
        let request = streamingRequestBody
        let expected = try TokenEstimator.estimate(request)
        let resolver = GatewayInitialUsageResolverProbe(
            mode: .fixed(
                .localEstimate(
                    tokens: expected,
                    providerOutcome: .timeout,
                    elapsedMilliseconds: 1_000
                )
            )
        )
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                chunks: [gatewayInitialUsageUTF8(zeroWire)]
            )
        ])
        let recorder = TrafficTestRecorder()
        let app = application(
            fixture: fixture,
            transport: transport,
            resolver: resolver,
            recorder: recorder
        )

        let clientBody = try await executeStreamingRequest(app: app, body: request)
        let clientText = try #require(String(data: clientBody, encoding: .utf8))

        #expect(clientText.contains(#""input_tokens":\#(expected)"#))
        #expect(
            recorder.events.first?.initialUsageEstimate
                == TrafficInitialUsageEstimate(
                    tokenCount: expected,
                    source: .localDividedByFour,
                    providerOutcome: .timeout,
                    elapsedMilliseconds: 1_000
                )
        )
    }

    @Test("Non-eligible responses never invoke initial-usage resolution")
    func ineligibleResponsesStayOnExistingPath() async throws {
        try await assertResolverNotCalled(
            streaming: false,
            status: .ok,
            headers: [
                "content-type": "text/event-stream"
            ]
        )
        try await assertResolverNotCalled(
            streaming: true,
            status: .internalServerError,
            headers: [
                "content-type": "text/event-stream"
            ]
        )
        try await assertResolverNotCalled(
            streaming: true,
            status: .ok,
            headers: [
                "content-type": "application/json"
            ]
        )
        try await assertResolverNotCalled(streaming: true, status: .ok, headers: [:])
    }

    @Test("Image retry resolves against the replacement body that produced the stream")
    func imageRetryUsesReplacementBody() async throws {
        let fixture = try GatewayTests().makeFixture()
        let unsupported =
            #"{"type":"error","error":{"type":"invalid_request_error","message":"This model does not support image input"}}"#
        let transport = RecordingGatewayTransport(responses: [
            response(status: .badRequest, body: unsupported),
            streamingResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                chunks: [gatewayInitialUsageUTF8(zeroWire)]
            ),
        ])
        let resolver = GatewayInitialUsageResolverProbe(
            mode: .fixed(.providerEstimate(tokens: 12, elapsedMilliseconds: 4))
        )
        let app = application(
            fixture: fixture,
            transport: transport,
            resolver: resolver,
            recorder: TrafficTestRecorder()
        )
        let request = Data(
            (#"{"model":"claude-opus-5","stream":true,"messages":[{"role":"user","content":["#
                + #"{"type":"image","source":{"type":"base64","media_type":"image/png","#
                + #""data":"private-image"}},{"type":"text","text":"keep"}]}]}"#)
                .utf8
        )

        _ = try await executeStreamingRequest(app: app, body: request)

        let requests = await transport.requests
        let contexts = await resolver.requests
        #expect(requests.count == 2)
        #expect(contexts.count == 1)
        let context = try #require(contexts.first)
        #expect(context.upstreamBody == requests[1].body)
        #expect(context.upstreamBody != requests[0].body)
        let replacementText = gatewayInitialUsageUTF8(context.upstreamBody)
        #expect(!replacementText.contains("private-image"))
        #expect(replacementText.contains("keep"))
    }

    @Test("The gateway does not read another SSE chunk while count resolution is pending")
    func resolverPreservesUpstreamBackpressure() async throws {
        let fixture = try GatewayTests().makeFixture()
        let gate = GatewayExecutionGate()
        let resolver = GatewayInitialUsageResolverProbe(
            mode: .gated(
                gate,
                .providerEstimate(tokens: 7, elapsedMilliseconds: 3)
            )
        )
        let upstreamBody = GatewayGatedBody(chunks: [zeroStartFrame, terminalFrame])
        let upstream = HTTPClientResponse(
            status: .ok,
            headers: ["content-type": "text/event-stream"],
            body: .stream(upstreamBody)
        )
        let responder = responder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: []),
            resolver: resolver
        )
        let response = try await responder.providerResponse(
            upstream,
            context: try attemptContext(fixture: fixture, streaming: true)
        )

        let task = Task { try await responseBodyData(response.body) }
        try await gate.waitUntilEntered()

        #expect(await upstreamBody.readCount == 1)
        await gate.release()
        let output = try await task.value
        #expect(output.suffix(terminalFrame.count) == terminalFrame)
        #expect(await upstreamBody.readCount == 2)
    }

    @Test("An adapted SSE drops stale body validators and delivers the complete stream")
    func adaptedStreamDropsStaleBodyValidators() async throws {
        let fixture = try GatewayTests().makeFixture()
        let upstream = streamingResponse(
            status: .ok,
            headers: [
                "content-type": "text/event-stream",
                "content-length": String(zeroWire.count),
                "etag": #""provider-body""#,
                "content-digest": "sha-256=:stale:",
            ],
            chunks: irregularChunks(of: zeroWire)
        )
        let response = try await responder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: []),
            resolver: GatewayInitialUsageResolverProbe(
                mode: .fixed(.providerEstimate(tokens: 12_345, elapsedMilliseconds: 4))
            )
        ).providerResponse(
            upstream,
            context: try attemptContext(fixture: fixture, streaming: true)
        )
        let etag = try #require(HTTPField.Name("etag"))
        let contentDigest = try #require(HTTPField.Name("content-digest"))

        #expect(response.headers[.contentLength] == nil)
        #expect(response.headers[etag] == nil)
        #expect(response.headers[contentDigest] == nil)
        let body = try await responseBodyData(response.body)
        let text = try #require(String(data: body, encoding: .utf8))
        #expect(text.contains(#""input_tokens":12345"#))
        #expect(body.suffix(terminalFrame.count) == terminalFrame)
    }

    @Test("Resolver cancellation propagates and a failed client write never recounts")
    func cancellationAndWriterFailure() async throws {
        let fixture = try GatewayTests().makeFixture()
        let cancellationResolver = GatewayInitialUsageResolverProbe(mode: .cancellation)
        let cancellationResponse = try await responder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: []),
            resolver: cancellationResolver
        ).providerResponse(
            streamingResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                chunks: [gatewayInitialUsageUTF8(zeroWire)]
            ),
            context: try attemptContext(fixture: fixture, streaming: true)
        )
        await #expect(throws: CancellationError.self) {
            _ = try await responseBodyData(cancellationResponse.body)
        }
        #expect(await cancellationResolver.callCount == 1)

        let writerResolver = GatewayInitialUsageResolverProbe(
            mode: .fixed(.providerEstimate(tokens: 5, elapsedMilliseconds: 2))
        )
        let writerResponse = try await responder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: []),
            resolver: writerResolver
        ).providerResponse(
            streamingResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                chunks: [gatewayInitialUsageUTF8(zeroWire)]
            ),
            context: try attemptContext(fixture: fixture, streaming: true)
        )
        await #expect(throws: GatewayTestError.privateFailure) {
            try await writerResponse.body.write(CoverageThrowingWriter(failure: .error))
        }
        #expect(await writerResolver.callCount == 1)
    }

    private var zeroStartFrame: Data {
        Data(
            ("event: message_start\ndata: {\"type\":\"message_start\","
                + "\"message\":{\"id\":\"msg_zai\",\"type\":\"message\","
                + "\"role\":\"assistant\",\"content\":[],\"model\":\"glm\","
                + "\"stop_reason\":null,\"stop_sequence\":null,"
                + "\"usage\":{\"input_tokens\":0,\"output_tokens\":0}}}\n\n")
                .utf8
        )
    }

    private var terminalFrame: Data {
        Data(
            ("event: message_delta\ndata: {\"type\":\"message_delta\","
                + "\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},"
                + "\"usage\":{\"input_tokens\":41,\"cache_read_input_tokens\":1472,"
                + "\"output_tokens\":7}}\n\n"
                + "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n")
                .utf8
        )
    }

    private var zeroWire: Data {
        zeroStartFrame + terminalFrame
    }

    private var nativeWire: Data {
        Data(
            (": keepalive\r\nevent: message_start\r\n"
                + "data: {\"type\":\"message_start\",\"message\":{\"usage\":"
                + "{\"output_tokens\":0,\"input_tokens\":23},\"content\":[]}}\r\n\r\n"
                + "event: content_block_delta\r\n"
                + "data: {\"type\":\"content_block_delta\",\"delta\":"
                + "{\"type\":\"text_delta\",\"text\":\"OK\"}}\r\n\r\n"
                + "event: message_delta\r\n"
                + "data: {\"type\":\"message_delta\",\"usage\":{\"output_tokens\":1}}"
                + "\r\n\r\n")
                .utf8
        )
    }

    private var streamingRequestBody: Data {
        Data(
            #"{"model":"claude-opus-5","stream":true,"max_tokens":32,"messages":[{"role":"user","content":"Réponds OK."}]}"#
                .utf8
        )
    }

    private func irregularChunks(of data: Data) -> [String] {
        let boundaries = [1, 7, 19, 43, 89, data.count]
        var start = 0
        return boundaries.compactMap { end in
            let upper = min(end, data.count)
            guard upper > start else { return nil }
            defer { start = upper }
            return gatewayInitialUsageUTF8(data[start..<upper])
        }
    }

    private func occurrences(of needle: Data, in haystack: Data) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var cursor = haystack.startIndex
        while cursor < haystack.endIndex {
            guard let range = haystack.range(of: needle, in: cursor..<haystack.endIndex) else {
                break
            }
            count += 1
            cursor = range.upperBound
        }
        return count
    }

    private func executeStreamingRequest(
        app: Application<GatewayResponder>,
        body: Data? = nil
    ) async throws -> Data {
        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body ?? streamingRequestBody)
            )
            return data(response.body)
        }
    }

    private func assertResolverNotCalled(
        streaming: Bool,
        status: HTTPResponseStatus,
        headers: HTTPHeaders
    ) async throws {
        let fixture = try GatewayTests().makeFixture()
        let resolver = GatewayInitialUsageResolverProbe(mode: .forbidden)
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: status,
                headers: headers,
                chunks: [gatewayInitialUsageUTF8(zeroWire)]
            )
        ])
        let app = application(
            fixture: fixture,
            transport: transport,
            resolver: resolver,
            recorder: TrafficTestRecorder()
        )
        var request = try #require(
            JSONSerialization.jsonObject(with: streamingRequestBody) as? [String: Any]
        )
        request["stream"] = streaming
        let body = try JSONSerialization.data(withJSONObject: request)

        _ = try await executeStreamingRequest(app: app, body: body)

        #expect(await resolver.callCount == 0)
    }

    private func application(
        fixture: GatewayFixture,
        transport: any UpstreamTransport,
        resolver: any AnthropicInitialUsageResolving,
        recorder: any TrafficRecording
    ) -> Application<GatewayResponder> {
        Application(
            responder: responder(
                fixture: fixture,
                transport: transport,
                resolver: resolver,
                recorder: recorder
            )
        )
    }

    private func responder(
        fixture: GatewayFixture,
        transport: any UpstreamTransport,
        resolver: any AnthropicInitialUsageResolving,
        recorder: any TrafficRecording = NoopTrafficRecorder()
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

    private func attemptContext(
        fixture: GatewayFixture,
        streaming: Bool
    ) throws -> MessageAttemptContext {
        MessageAttemptContext(
            eventID: UUID(),
            target: try #require(fixture.snapshot.resolve(model: "claude-opus-5")),
            secret: "selected-secret",
            incomingHeaders: [:],
            upstreamBody: streamingRequestBody,
            streaming: streaming
        )
    }
}
