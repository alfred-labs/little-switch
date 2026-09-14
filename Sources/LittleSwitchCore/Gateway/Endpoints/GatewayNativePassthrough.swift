import AsyncHTTPClient
import Foundation
import Hummingbird
import NIOHTTP1

extension GatewayResponder {
    /// Relays native operations with the client's own credentials. Neither the
    /// selected custom provider nor its credentials participate in this exchange.
    package func nativePassthroughResponse(
        body: Data,
        incomingHeaders: HTTPHeaders,
        endpoint: CodexNativePassthrough.Endpoint,
        eventID: UUID
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
        let upstream: HTTPClientResponse
        do {
            try Task.checkCancellation()
            upstream = try await transport.execute(upstreamRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return openAIError(status: .badGateway, message: "Provider request failed")
        }
        if endpoint == .responses {
            return nativeResponsesStream(upstream, eventID: eventID)
        }
        recordUpstreamResponseHead(eventID: eventID, attempt: 0, response: upstream)
        return streamingResponse(upstream, eventID: eventID, attempt: 0)
    }
}
