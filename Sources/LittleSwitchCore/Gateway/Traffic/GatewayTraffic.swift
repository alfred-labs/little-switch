import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchCommon
import NIOCore
import NIOHTTP1
import os

package struct MessageAttemptContext: Sendable {
    let eventID: UUID
    let target: RoutedTarget
    let secret: String?
    let incomingHeaders: HTTPHeaders
    let upstreamBody: Data
    let streaming: Bool
}

/// The client-facing route and the resolved provider target of a Responses
/// request — the pair every upstream traffic record on that wire needs.
package struct ResponsesTrafficRoute: Sendable {
    let claudeRoute: String
    let target: CodexModelTarget

    package init(claudeRoute: String, target: CodexModelTarget) {
        self.claudeRoute = claudeRoute
        self.target = target
    }
}

extension GatewayResponder {
    package func providerResponse(
        _ firstResponse: HTTPClientResponse,
        context: MessageAttemptContext,
        trace suppliedTrace: GatewayUpstreamResponseTrace? = nil
    ) async throws -> Response {
        let trace = suppliedTrace ?? upstreamResponseTrace(eventID: context.eventID, attempt: 0)
        guard firstResponse.status == .badRequest else {
            return anthropicInitialUsageResponse(
                firstResponse,
                context: context,
                attempt: 0,
                requestBody: context.upstreamBody,
                trace: trace
            )
        }

        let firstBody: Data
        do {
            try Task.checkCancellation()
            firstBody = try await trace.collect(firstResponse.body, upTo: maximumErrorBytes)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return anthropicError(
                status: .badGateway,
                message: "Provider error response exceeded the limit"
            )
        }
        guard
            ImageFallback.shouldRetry(
                status: Int(firstResponse.status.code),
                responseBody: firstBody,
                originalRequest: context.upstreamBody
            ), let replacement = try? ImageFallback.replacingImages(in: context.upstreamBody)
        else {
            return bufferedResponse(firstResponse, body: firstBody)
        }
        trafficRecorder.record(eventID: context.eventID, action: .imageRetry)

        let retryRequest: HTTPClientRequest
        do {
            try Task.checkCancellation()
            retryRequest = try dependencies.retryRequestBuilder.message(
                provider: context.target.provider,
                secret: context.secret,
                headers: context.incomingHeaders,
                body: replacement.body
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return anthropicError(status: .badGateway, message: "Provider retry failed")
        }
        let upstreamTraffic = trafficUpstreamRequest(
            attempt: 1,
            target: context.target,
            request: retryRequest,
            body: replacement.body,
            streaming: context.streaming
        )
        do {
            try Task.checkCancellation()
            let retryResponse = try await executeModelRequest(
                retryRequest,
                body: replacement.body,
                traffic: upstreamTraffic,
                wire: .anthropic,
                eventID: context.eventID,
                attempt: 1
            )
            try Task.checkCancellation()
            return anthropicInitialUsageResponse(
                retryResponse.response,
                context: context,
                attempt: 1,
                requestBody: replacement.body,
                trace: retryResponse.trace
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return anthropicError(status: .badGateway, message: "Provider retry failed")
        }
    }

    package func trafficUpstreamRequest(
        attempt: Int,
        target: RoutedTarget,
        request: HTTPClientRequest,
        body: Data,
        streaming: Bool
    ) -> TrafficUpstreamRequest {
        TrafficUpstreamRequest(
            attempt: attempt,
            claudeRoute: target.route.id,
            providerID: target.provider.id,
            providerName: target.provider.name,
            modelID: target.modelID,
            url: TrafficRedactor.url(request.url),
            headers: TrafficRedactor.headers(request.headers),
            body: body,
            streaming: streaming
        )
    }

    package func trafficUpstreamRequest(
        attempt: Int,
        route: ResponsesTrafficRoute,
        request: HTTPClientRequest,
        body: Data,
        streaming: Bool
    ) -> TrafficUpstreamRequest {
        TrafficUpstreamRequest(
            attempt: attempt,
            claudeRoute: route.claudeRoute,
            providerID: route.target.provider.id,
            providerName: route.target.provider.name,
            modelID: route.target.model.id,
            url: TrafficRedactor.url(request.url),
            headers: TrafficRedactor.headers(request.headers),
            body: body,
            streaming: streaming
        )
    }

    package func trafficRoute(
        client: GatewayClient,
        modelIdentifier: String,
        target: RoutedTarget,
        streaming: Bool
    ) -> TrafficRoute {
        TrafficRoute(
            client: client,
            modelIdentifier: modelIdentifier,
            target: TrafficRouteTarget(
                providerID: target.provider.id,
                providerName: target.provider.name,
                modelID: target.modelID
            ),
            streaming: streaming
        )
    }

    package func trafficRoute(
        client: GatewayClient,
        modelIdentifier: String,
        target: CodexModelTarget,
        streaming: Bool
    ) -> TrafficRoute {
        TrafficRoute(
            client: client,
            modelIdentifier: modelIdentifier,
            target: TrafficRouteTarget(
                providerID: target.provider.id,
                providerName: target.provider.name,
                modelID: target.model.id
            ),
            streaming: streaming
        )
    }

    package func recordUpstreamResponseHead(
        eventID: UUID,
        attempt: Int,
        response: HTTPClientResponse
    ) {
        trafficRecorder.record(
            eventID: eventID,
            action: .upstreamResponseHead(
                TrafficUpstreamResponseHead(
                    attempt: attempt,
                    status: Int(response.status.code),
                    headers: TrafficRedactor.headers(response.headers)
                )
            )
        )
    }

    package func recordingClientResponse(
        _ response: Response,
        eventID: UUID,
        permitCompletion: GatewayPermitCompletionGuard? = nil,
        terminalFailure: TrafficFailure? = nil
    ) -> Response {
        let status = response.status.code
        let monitoring = GatewayMonitoringScope.current
        let isEventStream =
            response.headers[.contentType]?
            .split(separator: ";")
            .first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() == "text/event-stream"
        let recorder = trafficRecorder
        recorder.record(
            eventID: eventID,
            action: .clientResponseHead(
                TrafficClientResponseHead(
                    status: status,
                    headers: TrafficRedactor.headers(response.headers)
                )
            )
        )

        let contentLength = response.body.contentLength
        let clientChunks = ClientTrafficChunkRecorder(
            recorder: recorder,
            eventID: eventID
        )
        let recordedBody = response.body.map { buffer in
            clientChunks.append(Data(buffer.readableBytesView))
            return buffer
        }
        let body = ResponseBody(contentLength: contentLength) { writer in
            do {
                try Task.checkCancellation()
                try await GatewayMonitoringScope.$current.withValue(monitoring) {
                    if let monitoring, isEventStream, status < 400 {
                        try await recordedBody.write(MonitoringResponseBodyWriter(writer: writer, context: monitoring))
                    } else {
                        try await recordedBody.write(writer)
                    }
                }
                try Task.checkCancellation()
                clientChunks.flush()
                await permitCompletion?.finish()
                await monitoring?.finish(statusCode: status)
                recorder.record(
                    eventID: eventID,
                    action: terminalAction(
                        status: status,
                        finishedAt: Date(),
                        failure: terminalFailure
                    )
                )
            } catch let committed as GatewayCommittedStreamFailure {
                clientChunks.flush()
                await permitCompletion?.finish()
                await monitoring?.finish(statusCode: status, error: .transport)
                recorder.record(
                    eventID: eventID,
                    action: .failed(
                        TrafficFailureCompletion(
                            status: status,
                            finishedAt: Date(),
                            failure: committed.trafficFailure
                        )
                    )
                )
            } catch is CancellationError {
                clientChunks.flush()
                await permitCompletion?.finish()
                await monitoring?.finish(statusCode: status, error: .cancelled)
                recorder.record(eventID: eventID, action: .cancelled(finishedAt: Date()))
                throw CancellationError()
            } catch {
                clientChunks.flush()
                await permitCompletion?.finish()
                await monitoring?.finish(statusCode: status, error: .transport)
                recorder.record(
                    eventID: eventID,
                    action: .failed(
                        TrafficFailureCompletion(
                            status: status,
                            finishedAt: Date(),
                            failure: TrafficFailure(
                                kind: "stream",
                                message: "Response streaming failed"
                            )
                        )
                    )
                )
                throw error
            }
        }
        return Response(status: response.status, headers: response.headers, body: body)
    }

    package func streamingResponse(
        _ upstream: HTTPClientResponse,
        eventID: UUID,
        attempt: Int,
        errorStyle: ErrorStyle? = nil,
        trace suppliedTrace: GatewayUpstreamResponseTrace? = nil
    ) -> Response {
        let trace = suppliedTrace ?? upstreamResponseTrace(eventID: eventID, attempt: attempt)
        let upstreamBody = upstream.body
        let streaming = upstream.headers["content-type"].contains { $0.lowercased().contains("text/event-stream") }
        let canRewrite = errorStyle != nil && (200..<300).contains(upstream.status.code) && streaming
        return Response(
            status: httpStatus(upstream.status),
            headers: canRewrite
                ? gatewayRewrittenResponseHeaders(upstream.headers) : gatewayResponseHeaders(upstream.headers),
            body: ResponseBody(contentLength: nil) { writer in
                defer { trace.finish() }
                do {
                    for try await buffer in upstreamBody {
                        trace.append(Data(buffer.readableBytesView))
                        try await writer.write(buffer)
                    }
                    try await writer.finish(nil)
                } catch let error as ProviderToolContract.Error {
                    guard let errorStyle else { throw error }
                    let frame = providerToolFailureFrame(style: errorStyle, error: error, eventID: eventID)
                    try await writer.write(ByteBuffer(bytes: frame))
                    try await writer.finish(nil)
                    throw GatewayCommittedStreamFailure(reason: "Provider tool contract rejected", toolError: error)
                }
            }
        )
    }

    package func bufferedResponse(_ upstream: HTTPClientResponse, body: Data) -> Response {
        Response(
            status: httpStatus(upstream.status),
            headers: gatewayResponseHeaders(upstream.headers),
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: body))
        )
    }
}

/// Records client-bound chunks through a synchronous lock rather than an
/// actor: the recorder runs inside ResponseBody.map's Sendable closure on
/// every streamed chunk, where an actor hop per network buffer is the
/// difference between zero-cost passthrough and a suspension per chunk.
private final class ClientTrafficChunkRecorder: Sendable {
    private let recorder: any TrafficRecording
    private let eventID: UUID
    private let chunks: OSAllocatedUnfairLock<TrafficChunkCoalescer>

    init(recorder: any TrafficRecording, eventID: UUID) {
        self.recorder = recorder
        self.eventID = eventID
        self.chunks = OSAllocatedUnfairLock(initialState: TrafficChunkCoalescer())
    }

    func append(_ bytes: Data) {
        let emitted = chunks.withLock { $0.append(bytes) }
        recordTrafficChunks(
            emitted,
            target: .client,
            recorder: recorder,
            eventID: eventID
        )
    }

    func flush() {
        let emitted = chunks.withLock { $0.flush() }
        recordTrafficChunks(
            emitted,
            target: .client,
            recorder: recorder,
            eventID: eventID
        )
    }
}

private func terminalAction(
    status: Int,
    finishedAt: Date,
    failure: TrafficFailure? = nil
) -> TrafficAction {
    if let failure {
        return .failed(
            TrafficFailureCompletion(
                status: status,
                finishedAt: finishedAt,
                failure: failure
            )
        )
    }
    if status >= 400 {
        return .failed(
            TrafficFailureCompletion(
                status: status,
                finishedAt: finishedAt,
                failure: TrafficFailure(kind: "http", message: "HTTP \(status)")
            )
        )
    }
    return .completed(TrafficCompletion(status: status, finishedAt: finishedAt))
}

private func httpStatus(_ status: HTTPResponseStatus) -> HTTPResponse.Status {
    HTTPResponse.Status(code: Int(status.code), reasonPhrase: status.reasonPhrase)
}

package func gatewayResponseHeaders(_ headers: HTTPHeaders) -> HTTPFields {
    var excluded = Set([
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
    ]).union(
        headers["connection"].flatMap { value in
            value.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        }
    )
    let contentEncodings = headers["content-encoding"].flatMap { value in
        value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }
    let wasAutomaticallyDecompressed =
        !contentEncodings.isEmpty
        && contentEncodings.allSatisfy { $0 == "gzip" || $0 == "deflate" }
    if wasAutomaticallyDecompressed {
        excluded.formUnion(["content-encoding", "content-length"])
    }
    var fields = HTTPFields()
    for (name, value) in headers where !excluded.contains(name.lowercased()) {
        guard let fieldName = HTTPField.Name(name) else {
            continue
        }
        fields.append(HTTPField(name: fieldName, value: value))
    }
    return fields
}
