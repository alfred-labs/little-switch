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

extension GatewayTests {
    @Test("Messages rewrite only model, preserve safe headers, and stream bytes")
    func messageStreaming() async throws {
        let fixture = try makeFixture()
        let chunks = ["data: {\"type\":\"ping\",\"seq\":1}\n\n", "data: {\"type\":\"ping\",\"seq\":2}\n\n"]
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .ok,
                headers: [
                    "content-type": "text/event-stream",
                    "x-upstream": "yes",
                    "connection": "close",
                ],
                chunks: chunks
            )
        ])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(
            fixture: fixture,
            transport: transport,
            trafficRecorder: recorder
        )
        let beta = try #require(HTTPField.Name("anthropic-beta"))
        let upstream = try #require(HTTPField.Name("x-upstream"))
        let body =
            #"{"model":"claude-opus-5[1m]","stream":true,"metadata":{"opaque":7},"tools":[{"name":"weather"}],"messages":[{"role":"user","content":"hello"}]}"#

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "incoming-secret",
                    .cookie: "ambient=secret",
                    beta: "tools-2026",
                ],
                body: ByteBuffer(string: body)
            )

            #expect(response.status == .ok)
            #expect(String(buffer: response.body) == chunks.joined())
            #expect(response.headers[.contentType] == "text/event-stream")
            #expect(response.headers[upstream] == "yes")
            #expect(response.headers[.connection] == nil)

            let request = try #require(await transport.requests.first)
            #expect(request.url == "https://api.z.ai/api/anthropic/v1/messages")
            #expect(request.headers["authorization"] == ["Bearer selected-secret"])
            #expect(request.headers["cookie"].isEmpty)
            #expect(request.headers["anthropic-beta"] == ["tools-2026"])
            let root = try #require(
                JSONSerialization.jsonObject(with: request.body) as? [String: Any]
            )
            #expect(root["model"] as? String == "glm-5.2")
            #expect((root["metadata"] as? [String: Int])?["opaque"] == 7)
            #expect((root["tools"] as? [[String: String]])?.first?["name"] == "weather")
            #expect(await fixture.state.sessionRequestCount == 1)
        }

        let event = try #require(recorder.events.first)
        #expect(event.lifecycle == .completed)
        #expect(event.claudeRoute == "claude-opus-5")
        #expect(event.providerName == "z.ai")
        #expect(event.modelID == "glm-5.2")
        #expect(event.streaming)
        #expect(String(data: event.claudeRequest.body, encoding: .utf8) == body)
        #expect(header("authorization", in: event.claudeRequest.headers) == TrafficRedactor.mask)
        let exchange = try #require(event.upstreamExchanges.first)
        #expect(exchange.request?.url == "https://api.z.ai/api/anthropic/v1/messages")
        #expect(header("authorization", in: exchange.request?.headers ?? []) == TrafficRedactor.mask)
        #expect(String(data: exchange.request?.body ?? Data(), encoding: .utf8)?.contains("glm-5.2") == true)
        #expect(String(data: exchange.response.body, encoding: .utf8) == chunks.joined())
        #expect(exchange.response.body == event.clientResponse.body)
        #expect(event.finalStatus == 200)
        let structured = String(data: try JSONEncoder().encode(event), encoding: .utf8)
        #expect(structured?.contains("incoming-secret") == false)
        #expect(structured?.contains("selected-secret") == false)
    }

    @Test("Unsupported images retry once on the same target without double counting")
    func imageRetry() async throws {
        let fixture = try makeFixture()
        let unsupported =
            #"{"type":"error","error":{"type":"invalid_request_error","message":"This model does not support image input"}}"#
        let transport = RecordingGatewayTransport(responses: [
            response(status: .badRequest, body: unsupported),
            response(status: .ok, body: #"{"type":"message","content":[]}"#),
        ])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(
            fixture: fixture,
            transport: transport,
            trafficRecorder: recorder
        )
        let request =
            #"{"model":"claude-opus-5","messages":[{"role":"user","content":[{"type":"image","source":{"type":"base64","data":"private-image"}},{"type":"text","text":"keep"}]}]}"#

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: request)
            )
            #expect(result.status == .ok)

            let requests = await transport.requests
            #expect(requests.count == 2)
            #expect(requests[0].url == requests[1].url)
            #expect(requests[0].headers["authorization"] == requests[1].headers["authorization"])
            let retry = try #require(String(data: requests[1].body, encoding: .utf8))
            #expect(retry.contains(ImageFallback.notice))
            #expect(!retry.contains("private-image"))
            #expect(retry.contains("keep"))
            #expect(await fixture.state.sessionRequestCount == 1)
        }

        let event = try #require(recorder.events.first)
        #expect(event.didRetryImages)
        #expect(event.upstreamExchanges.count == 2)
        #expect(event.upstreamExchanges[0].responseStatus == 400)
        #expect(event.upstreamExchanges[1].responseStatus == 200)
        #expect(event.upstreamExchanges[0].request?.body != event.upstreamExchanges[1].request?.body)
        #expect(event.lifecycle == .completed)
    }

    @Test("Transport cancellation records cancellation and still propagates")
    func transportCancellation() async throws {
        let fixture = try makeFixture()
        let recorder = TrafficTestRecorder()
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: CancellingGatewayTransport(),
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                trafficRecorder: recorder
            )
        )

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(
                    string: #"{"model":"claude-opus-5","messages":[]}"#
                )
            )
            #expect(response.status == .internalServerError)
        }
        #expect(recorder.events.first?.lifecycle == .cancelled)
    }

    @Test("Oversized and erroring provider error bodies return a safe retry error")
    func providerErrorBodyFailures() async throws {
        let fixture = try makeFixture()
        let context = try messageAttemptContext(fixture: fixture)

        for firstResponse in [
            response(status: .badRequest, body: "private-overflow"),
            erroringGatewayResponse(status: .badRequest, error: GatewayTestError.privateFailure),
        ] {
            let responder = GatewayResponder(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: []),
                secretStore: fixture.secrets,
                maximumErrorBytes: 4,
                requiredAuthorityPort: nil
            )
            let result = try await responder.providerResponse(firstResponse, context: context)
            #expect(result.status == .badGateway)
            let body = try await responseBodyData(result.body)
            let text = String(data: body, encoding: .utf8) ?? ""
            #expect(text.contains("Provider error response exceeded the limit"))
            #expect(!text.contains("private"))
        }
    }

    @Test("Provider error body cancellation propagates and records cancellation")
    func providerErrorBodyCancellation() async throws {
        let fixture = try makeFixture()
        let recorder = TrafficTestRecorder()
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: SingleGatewayResponseTransport {
                    erroringGatewayResponse(
                        status: .badRequest,
                        error: CancellationError()
                    )
                },
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                trafficRecorder: recorder
            )
        )

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(string: #"{"model":"claude-opus-5","messages":[]}"#)
            )
            #expect(result.status == .internalServerError)
        }

        let event = try #require(recorder.events.first)
        #expect(event.lifecycle == .cancelled)
        #expect(event.finalStatus == nil)
    }

    @Test("A non-image bad request passes through its buffered provider response")
    func nonImageBadRequestPassthrough() async throws {
        let fixture = try makeFixture()
        let upstreamBody = #"{"type":"error","error":{"message":"ordinary bad request"}}"#
        let transport = RecordingGatewayTransport(responses: [])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let result = try await responder.providerResponse(
            response(status: .badRequest, body: upstreamBody),
            context: try messageAttemptContext(fixture: fixture)
        )

        #expect(result.status == .badRequest)
        #expect(String(data: try await responseBodyData(result.body), encoding: .utf8) == upstreamBody)
        #expect(await transport.requests.isEmpty)
    }

    @Test("Retry build and execution failures never expose the first provider body")
    func retryFailures() async throws {
        let fixture = try makeFixture()
        let privateBody =
            #"{"type":"error","error":{"type":"invalid_request_error","message":"This model does not support image input","private":"upstream"}}"#
        let first = response(status: .badRequest, body: privateBody)
        let buildTransport = RecordingGatewayTransport(responses: [])
        let buildResponder = GatewayResponder(
            state: fixture.state,
            transport: buildTransport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            dependencies: GatewayResponderDependencies(
                retryRequestBuilder: ThrowingGatewayRetryRequestBuilder()
            )
        )
        let buildResult = try await buildResponder.providerResponse(
            first,
            context: try messageAttemptContext(fixture: fixture)
        )
        #expect(buildResult.status == .badGateway)
        let buildBody =
            String(
                data: try await responseBodyData(buildResult.body),
                encoding: .utf8
            ) ?? ""
        #expect(buildBody.contains("Provider retry failed"))
        #expect(!buildBody.contains("upstream"))
        #expect(await buildTransport.requests.isEmpty)

        let executeResponder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let executeResult = try await executeResponder.providerResponse(
            response(status: .badRequest, body: privateBody),
            context: try messageAttemptContext(fixture: fixture)
        )
        #expect(executeResult.status == .badGateway)
        let executeBody =
            String(
                data: try await responseBodyData(executeResult.body),
                encoding: .utf8
            ) ?? ""
        #expect(executeBody.contains("Provider retry failed"))
        #expect(!executeBody.contains("upstream"))
    }

    @Test("Retry cancellation propagates")
    func retryCancellation() async throws {
        let fixture = try makeFixture()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: CancellingGatewayTransport(),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let privateBody =
            #"{"type":"error","error":{"type":"invalid_request_error","message":"This model does not support image input"}}"#

        await #expect(throws: CancellationError.self) {
            _ = try await responder.providerResponse(
                response(status: .badRequest, body: privateBody),
                context: try messageAttemptContext(fixture: fixture)
            )
        }
    }

    @Test("Client response stream cancellation and failure have distinct safe lifecycle records")
    func clientStreamFailures() async throws {
        for (error, lifecycle, kind) in [
            (CancellationError() as any Swift.Error, TrafficLifecycle.cancelled, nil),
            (GatewayTestError.privateFailure as any Swift.Error, TrafficLifecycle.failed, "stream"),
        ] {
            let fixture = try makeFixture()
            let recorder = TrafficTestRecorder()
            let app = Application(
                responder: GatewayResponder(
                    state: fixture.state,
                    transport: SingleGatewayResponseTransport {
                        var response = erroringGatewayResponse(status: .ok, error: error)
                        response.headers.replaceOrAdd(name: "content-type", value: "text/event-stream")
                        return response
                    },
                    secretStore: fixture.secrets,
                    requiredAuthorityPort: nil,
                    trafficRecorder: recorder
                )
            )

            await #expect(throws: (any Swift.Error).self) {
                _ = try await app.test(.router) { client in
                    try await client.execute(
                        uri: "/v1/messages",
                        method: .post,
                        body: ByteBuffer(
                            string: #"{"model":"claude-opus-5","messages":[]}"#
                        )
                    )
                }
            }
            let event = try #require(recorder.events.first)
            #expect(event.lifecycle == lifecycle)
            #expect(event.failure?.kind == kind)
            #expect((event.failure?.message.contains("private") ?? false) == false)
        }
    }

    @Test("A committed protocol failure is absorbed and recorded as failed")
    func committedProtocolFailureLifecycle() async throws {
        let fixture = try makeFixture()
        let recorder = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder
        )
        let eventID = UUID()
        let safeFrame = Data("event: error\ndata: {\"message\":\"Internal server error\"}\n\n".utf8)
        let response = Response(
            status: .ok,
            headers: [.contentType: "text/event-stream"],
            body: ResponseBody(contentLength: nil) { writer in
                try await writer.write(ByteBuffer(bytes: safeFrame))
                try await writer.finish(nil)
                throw GatewayCommittedStreamFailure()
            }
        )

        let recorded = responder.recordingClientResponse(response, eventID: eventID)
        let body = try await responseBodyData(recorded.body)

        #expect(body == safeFrame)
        let event = try #require(recorder.events.first)
        #expect(event.lifecycle == .failed)
        #expect(event.finalStatus == 200)
        #expect(event.failure?.kind == "stream")
        #expect(event.failure?.message == "Response stream reported failure")
    }

    @Test("Gateway response headers remove connection tokens, invalid names, and stale decompression metadata")
    func responseHeaderFiltering() throws {
        var headers = HTTPHeaders()
        headers.add(name: "connection", value: "x-private, keep-alive")
        headers.add(name: "x-private", value: "secret")
        headers.add(name: "x-keep", value: "visible")
        headers.add(name: "bad header", value: "invalid")
        let filtered = gatewayResponseHeaders(headers)
        let keep = try #require(HTTPField.Name("x-keep"))
        #expect(filtered[keep] == "visible")
        #expect(filtered.contains { $0.value == "secret" } == false)
        #expect(filtered.contains { $0.value == "invalid" } == false)

        let decompressed = gatewayResponseHeaders([
            "content-encoding": "gzip, deflate",
            "content-length": "99",
            "x-keep": "visible",
        ])
        #expect(decompressed[.contentEncoding] == nil)
        #expect(decompressed[.contentLength] == nil)

        let untouched = gatewayResponseHeaders([
            "content-encoding": "zstd",
            "content-length": "99",
        ])
        #expect(untouched[.contentEncoding] == "zstd")
        #expect(untouched[.contentLength] == "99")
    }

    private func messageAttemptContext(fixture: GatewayFixture) throws -> MessageAttemptContext {
        let target = try #require(fixture.snapshot.resolve(model: "claude-opus-5"))
        return MessageAttemptContext(
            eventID: UUID(),
            target: target,
            secret: "selected-secret",
            incomingHeaders: [:],
            upstreamBody: Data(
                #"{"model":"glm-5.2","messages":[{"role":"user","content":[{"type":"image","source":{"type":"base64","data":"private"}}]}]}"#
                    .utf8
            ),
            streaming: false
        )
    }
}

/// Vends one fresh response per execute: `HTTPClientResponse` bodies are
/// single-use sequences, so a shared instance cannot serve two exchanges —
/// the quota injection's monitor round-trip made that contract load-bearing
/// here.
private actor SingleGatewayResponseTransport: UpstreamTransport {
    private let makeResponse: @Sendable () -> HTTPClientResponse

    init(makeResponse: @escaping @Sendable () -> HTTPClientResponse) {
        self.makeResponse = makeResponse
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        return makeResponse()
    }
}

private struct ThrowingGatewayRetryRequestBuilder: GatewayRetryRequestBuilding {
    func message(
        provider: Provider,
        secret: String?,
        headers: HTTPHeaders,
        body: Data
    ) throws -> HTTPClientRequest {
        _ = provider
        _ = secret
        _ = headers
        _ = body
        throw GatewayTestError.privateFailure
    }
}

private func erroringGatewayResponse(
    status: HTTPResponseStatus,
    error: any Swift.Error
) -> HTTPClientResponse {
    let stream = AsyncThrowingStream<ByteBuffer, any Swift.Error> { continuation in
        continuation.finish(throwing: error)
    }
    return HTTPClientResponse(status: status, body: .stream(stream))
}
