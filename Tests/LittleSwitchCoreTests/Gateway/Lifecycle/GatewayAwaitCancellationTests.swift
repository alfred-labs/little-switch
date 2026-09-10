import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchTransport
import Logging
import NIOCore
import NIOEmbedded
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("A successful body collection that marks cancellation still propagates")
    func successfulBodyCancellation() async throws {
        let fixture = try makeFixture()
        let recorder = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder
        )
        let requests = [
            ("/v1/messages", #"{"model":"claude-opus-5","messages":[]}"#),
            ("/v1/responses", #"{"model":"codex/unused","input":"hello"}"#),
            (
                "/v1/messages/count_tokens",
                #"{"model":"claude-opus-5","messages":[]}"#
            ),
        ]

        for (path, body) in requests {
            let wasCancelled = await gatewayCancellationObserved(
                responder: responder,
                path: path,
                body: RequestBody(
                    asyncSequence: SuccessfulCancellingGatewayBodySequence(body: body)
                )
            )
            #expect(wasCancelled)
            guard wasCancelled else {
                return
            }
        }

        #expect(recorder.events.count == 3)
        #expect(recorder.events.allSatisfy { $0.lifecycle == .cancelled })
        #expect(recorder.events.allSatisfy { $0.finalStatus == nil })
    }

    @Test("A successful admission that marks cancellation stops every direct caller")
    func successfulAdmissionCancellation() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let recorder = TrafficTestRecorder()
        let transport = RecordingGatewayTransport(responses: [])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder,
            dependencies: GatewayResponderDependencies(
                admitter: SuccessfulCancellingGatewayAdmitter()
            )
        )
        let slug = try responsesSlug(fixture)
        let requests = [
            ("/v1/messages", #"{"model":"claude-opus-5","messages":[]}"#),
            (
                "/v1/messages",
                #"{"model":"claude-opus-5","messages":[],"tools":[{"type":"web_search_20250305","max_uses":1}]}"#
            ),
            ("/v1/responses", #"{"model":"\#(slug)","input":"hello"}"#),
            ("/v1/responses", responsesWebSearchRequest(slug: slug)),
        ]

        for (path, body) in requests {
            let wasCancelled = await gatewayCancellationObserved(
                responder: responder,
                path: path,
                body: RequestBody(buffer: ByteBuffer(string: body))
            )
            #expect(wasCancelled)
            guard wasCancelled else {
                return
            }
        }

        #expect(recorder.events.count == 4)
        #expect(recorder.events.allSatisfy { $0.lifecycle == .cancelled })
        #expect(recorder.events.allSatisfy { $0.finalStatus == nil })
        #expect(await transport.requests.isEmpty)
    }

    @Test("A successful direct provider response that marks cancellation is not projected")
    func successfulDirectProviderCancellation() async throws {
        let fixture = try makeFixture()
        let recorder = TrafficTestRecorder()
        let transport = AwaitBoundaryGatewayTransport(steps: [
            .cancelAndRespond(response(status: .ok, body: #"{"type":"message"}"#)),
            .cancelAndRespond(response(status: .ok, body: #"{"object":"response"}"#)),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder
        )
        let slug = try responsesSlug(fixture)

        for (path, body) in [
            ("/v1/messages", #"{"model":"claude-opus-5","messages":[]}"#),
            ("/v1/responses", #"{"model":"\#(slug)","input":"hello"}"#),
        ] {
            let wasCancelled = await gatewayCancellationObserved(
                responder: responder,
                path: path,
                body: RequestBody(buffer: ByteBuffer(string: body))
            )
            #expect(wasCancelled)
            guard wasCancelled else {
                return
            }
        }

        #expect(await transport.requestCount == 2)
        #expect(recorder.events.count == 2)
        #expect(recorder.events.allSatisfy { $0.lifecycle == .cancelled })
        #expect(
            recorder.events.allSatisfy {
                $0.upstreamExchanges.first?.responseStatus == 200
                    && $0.upstreamExchanges.first?.response.body.isEmpty == true
                    && $0.finalStatus == nil
            }
        )
    }

    @Test("A successful provider error body that marks cancellation prevents retry")
    func successfulProviderBodyCancellation() async throws {
        let fixture = try makeFixture()
        let recorder = TrafficTestRecorder()
        let transport = AwaitBoundaryGatewayTransport(steps: [
            .respond(
                cancellingSuccessfulGatewayResponse(
                    status: .badRequest,
                    body: unsupportedImageGatewayResponse
                )
            )
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder
        )

        let wasCancelled = await gatewayCancellationObserved(
            responder: responder,
            path: "/v1/messages",
            body: RequestBody(buffer: ByteBuffer(string: imageGatewayRequest))
        )
        #expect(wasCancelled)
        guard wasCancelled else {
            return
        }

        #expect(await transport.requestCount == 1)
        let event = try #require(recorder.events.first)
        #expect(event.lifecycle == .cancelled)
        #expect(!event.didRetryImages)
        #expect(event.upstreamExchanges.first?.response.body == Data(unsupportedImageGatewayResponse.utf8))
        #expect(event.finalStatus == nil)
    }

    @Test("A successful retry build that marks cancellation prevents retry execution")
    func successfulRetryBuildCancellation() async throws {
        let fixture = try makeFixture()
        let recorder = TrafficTestRecorder()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .badRequest, body: unsupportedImageGatewayResponse)
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder,
            dependencies: GatewayResponderDependencies(
                retryRequestBuilder: CancellingGatewayRetryBuilder()
            )
        )

        let wasCancelled = await gatewayCancellationObserved(
            responder: responder,
            path: "/v1/messages",
            body: RequestBody(buffer: ByteBuffer(string: imageGatewayRequest))
        )
        #expect(wasCancelled)
        guard wasCancelled else {
            return
        }

        #expect(await transport.requests.count == 1)
        let event = try #require(recorder.events.first)
        #expect(event.lifecycle == .cancelled)
        #expect(event.upstreamExchanges.count == 1)
    }

    @Test("A successful retry response that marks cancellation is not projected")
    func successfulRetryResponseCancellation() async throws {
        let fixture = try makeFixture()
        let recorder = TrafficTestRecorder()
        let transport = AwaitBoundaryGatewayTransport(steps: [
            .respond(response(status: .badRequest, body: unsupportedImageGatewayResponse)),
            .cancelAndRespond(response(status: .ok, body: #"{"type":"message"}"#)),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder
        )

        let wasCancelled = await gatewayCancellationObserved(
            responder: responder,
            path: "/v1/messages",
            body: RequestBody(buffer: ByteBuffer(string: imageGatewayRequest))
        )
        #expect(wasCancelled)
        guard wasCancelled else {
            return
        }

        #expect(await transport.requestCount == 2)
        let event = try #require(recorder.events.first)
        #expect(event.lifecycle == .cancelled)
        #expect(event.upstreamExchanges.count == 2)
        #expect(event.upstreamExchanges[1].responseStatus == 200)
        #expect(event.upstreamExchanges[1].response.body.isEmpty)
        #expect(event.finalStatus == nil)
    }

    @Test("A successful client body write that marks cancellation is not completed")
    func successfulClientBodyWriteCancellation() async throws {
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
        recorder.record(
            eventID: eventID,
            action: .started(
                TrafficRequestStart(
                    startedAt: Date(),
                    method: "GET",
                    path: "/stream",
                    headers: []
                )
            )
        )
        let response = responder.recordingClientResponse(
            Response(
                status: .ok,
                body: ResponseBody(contentLength: 0) { _ in
                    withUnsafeCurrentTask { task in
                        task?.cancel()
                    }
                }
            ),
            eventID: eventID
        )

        let task = Task {
            try await responseBodyData(response.body)
        }
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(recorder.events.first?.lifecycle == .cancelled)
    }

    @Test("A successful model catalog capture that marks cancellation is not returned")
    func modelCatalogCaptureCancellation() async throws {
        let fixture = try makeFixture()
        let recorder = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder,
            dependencies: GatewayResponderDependencies(
                snapshotCapturer: CancellingGatewaySnapshotCapturer()
            )
        )

        let wasCancelled = await gatewayCancellationObserved(
            responder: responder,
            method: .get,
            path: "/v1/models",
            body: RequestBody(buffer: ByteBuffer())
        )

        #expect(wasCancelled)
        #expect(recorder.events.first?.lifecycle == .cancelled)
        #expect(recorder.events.first?.finalStatus == nil)
    }
}

private struct CancellingGatewaySnapshotCapturer: GatewayRoutingSnapshotCapturing {
    func capture(state: GatewayState) async throws -> GatewayRoutingCapture {
        let snapshot = await state.routingCapture()
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
        return snapshot
    }
}

private let imageGatewayRequest =
    #"{"model":"claude-opus-5","messages":[{"role":"user","content":[{"type":"image","source":{"type":"base64","data":"private-image"}}]}]}"#

private let unsupportedImageGatewayResponse =
    #"{"type":"error","error":{"type":"invalid_request_error","message":"This model does not support image input"}}"#

private struct SuccessfulCancellingGatewayBodySequence: AsyncSequence, Sendable {
    typealias Element = ByteBuffer

    struct AsyncIterator: AsyncIteratorProtocol {
        var body: ByteBuffer?

        mutating func next() async throws -> ByteBuffer? {
            if let body {
                self.body = nil
                return body
            }
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return nil
        }
    }

    let body: String

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(body: ByteBuffer(string: body))
    }
}

private struct SuccessfulCancellingGatewayAdmitter: GatewayAdmitting {
    func admit(state: GatewayState, request: GatewayRequestAdmission) async throws {
        _ = state
        _ = request
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
    }
}

private enum AwaitBoundaryGatewayTransportStep: Sendable {
    case respond(HTTPClientResponse)
    case cancelAndRespond(HTTPClientResponse)
}

private actor AwaitBoundaryGatewayTransport: UpstreamTransport {
    private var steps: [AwaitBoundaryGatewayTransportStep]
    private(set) var requestCount = 0

    init(steps: [AwaitBoundaryGatewayTransportStep]) {
        self.steps = steps
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        requestCount += 1
        guard !steps.isEmpty else {
            throw GatewayTestError.failure
        }
        switch steps.removeFirst() {
        case .respond(let response):
            return response
        case .cancelAndRespond(let response):
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return response
        }
    }
}

private struct CancellingGatewayResponseSequence: AsyncSequence, Sendable {
    typealias Element = ByteBuffer

    struct AsyncIterator: AsyncIteratorProtocol {
        var body: ByteBuffer?

        mutating func next() async throws -> ByteBuffer? {
            if let body {
                self.body = nil
                return body
            }
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return nil
        }
    }

    let body: String

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(body: ByteBuffer(string: body))
    }
}

private struct CancellingGatewayRetryBuilder: GatewayRetryRequestBuilding {
    func message(
        provider: Provider,
        secret: String?,
        headers: HTTPHeaders,
        body: Data
    ) throws -> HTTPClientRequest {
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
        return try LiveGatewayRetryRequestBuilder().message(
            provider: provider,
            secret: secret,
            headers: headers,
            body: body
        )
    }
}

private func cancellingSuccessfulGatewayResponse(
    status: HTTPResponseStatus,
    body: String
) -> HTTPClientResponse {
    HTTPClientResponse(
        status: status,
        body: .stream(CancellingGatewayResponseSequence(body: body))
    )
}

private func gatewayCancellationObserved(
    responder: GatewayResponder,
    method: HTTPRequest.Method = .post,
    path: String,
    body: RequestBody
) async -> Bool {
    let request = Request(
        head: HTTPRequest(method: method, scheme: "http", authority: "localhost", path: path),
        body: body
    )
    let task = Task {
        let context = BasicRequestContext(
            source: ApplicationRequestContextSource(
                channel: EmbeddedChannel(),
                logger: Logger(label: #function)
            )
        )
        _ = try await responder.respond(to: request, context: context)
    }

    do {
        _ = try await task.value
        return false
    } catch is CancellationError {
        return true
    } catch {
        return false
    }
}
