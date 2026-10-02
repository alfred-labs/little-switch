import AsyncHTTPClient
import Foundation
import Hummingbird
import LittleSwitchCommon
import NIOHTTP1

extension GatewayResponder {
    /// Relays native operations with the client's own credentials. Neither the
    /// selected custom provider nor its credentials participate in this exchange.
    package func nativePassthroughResponse(
        body: Data,
        incomingHeaders: HTTPHeaders,
        endpoint: CodexNativePassthrough.Endpoint,
        eventID: UUID,
        requestedStreaming: Bool = false
    ) async throws -> Response {
        guard !CodexNativePassthrough.isSentinelAuthorization(incomingHeaders) else {
            return openAIError(
                status: .unauthorized,
                message: CodexNativePassthrough.sentinelRejectionMessage
            )
        }
        var upstreamRequest = HTTPClientRequest(
            url: CodexNativePassthrough.upstreamURL(
                accountSession: !incomingHeaders[CodexNativePassthrough.accountIDHeader].isEmpty, endpoint: endpoint
            )
        )
        upstreamRequest.method = .POST
        upstreamRequest.headers = CodexNativePassthrough.forwardedHeaders(incomingHeaders, endpoint: endpoint)
        upstreamRequest.body = .bytes(body)
        trafficRecorder.record(
            eventID: eventID,
            action: .annotation(
                TrafficAnnotation(
                    kind: "native-passthrough",
                    message: TrafficRedactor.url(upstreamRequest.url)
                )
            )
        )
        var upstream: HTTPClientResponse
        do {
            try Task.checkCancellation()
            let native = try await nativeWebSocketPassthroughResponse(
                upstreamRequest, body: body, endpoint: endpoint, eventID: eventID)
            if let native {
                upstream = native
            } else {
                transportDiagnosticObserver(eventID: eventID)(
                    "transport=http event=request-start requestBytes=\(body.count)")
                upstream = try await transport.execute(upstreamRequest)
            }
        } catch let failure as ResponsesWebSocketFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GatewayUpstreamRequestFailure(error)
        }
        if let monitoring = GatewayMonitoringScope.current {
            upstream.body = .stream(MonitoringProviderBody(body: upstream.body, context: monitoring))
        }
        if endpoint == .responses {
            return nativeResponsesStream(upstream, eventID: eventID, requestedStreaming: requestedStreaming)
        }
        recordUpstreamResponseHead(eventID: eventID, attempt: 0, response: upstream)
        return streamingResponse(upstream, eventID: eventID, attempt: 0)
    }

    private func nativeWebSocketPassthroughResponse(
        _ request: HTTPClientRequest, body: Data, endpoint: CodexNativePassthrough.Endpoint, eventID: UUID
    ) async throws -> HTTPClientResponse? {
        guard endpoint == .responses, let context = responsesWebSocketContext else { return nil }
        let observeControl: @Sendable (String) -> Void = { [trafficRecorder] type in
            trafficRecorder.record(
                eventID: eventID, action: .annotation(.init(kind: "websocket-steering", message: type)))
        }
        return try await context.execute(
            request: request,
            body: body,
            observeControl: observeControl,
            observeTransport: transportDiagnosticObserver(eventID: eventID))?.response
    }
}
