import AsyncHTTPClient
import Foundation

package func providerToolFailureFrame(
    style: GatewayResponder.ErrorStyle,
    error: ProviderToolContract.Error,
    eventID: UUID
) -> Data {
    // Only gateway-authored text and a UUID are interpolated, never provider data.
    let message: String
    if case .undeclaredTool = error {
        message = ResponsesPublicStreamSession.FailureWording.undeclaredTool(eventID).text
    } else {
        message = "Invalid provider tool response"
    }
    return switch style {
    case .anthropic:
        Data(
            "event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"\(message)\"}}\n\n"
                .utf8)
    case .openAI:
        Data(
            "event: error\ndata: {\"type\":\"error\",\"code\":\"server_error\",\"message\":\"\(message)\",\"param\":null}\n\n"
                .utf8)
    }
}

extension GatewayResponder {
    /// Every model exchange, including retries and bridge follow-ups, validates
    /// new tool output against the declarations on that exact upstream request.
    /// `declaredToolBindings` carries the request's own namespace flattening so
    /// a provider's near-miss name can be resolved back onto a declared wire
    /// name instead of killing the stream.
    package func executeModelRequest(
        _ request: HTTPClientRequest,
        body: Data,
        wire: ProviderToolContract.Wire,
        eventID: UUID,
        attempt: Int,
        declaredToolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
        toolNameCatalog: ProviderToolNameCatalog? = nil
    ) async throws -> GatewayModelExchange {
        try Task.checkCancellation()
        var response = try await transport.execute(request)
        if let monitoring = GatewayMonitoringScope.current {
            response.body = .stream(MonitoringProviderBody(body: response.body, context: monitoring))
        }
        let trace = upstreamResponseTrace(eventID: eventID, attempt: attempt)
        recordUpstreamResponseHead(eventID: eventID, attempt: attempt, response: response)
        let streaming = response.headers["content-type"].contains { $0.lowercased().contains("text/event-stream") }
        let collectsJSON = (200..<300).contains(response.status.code) && !streaming
        // JSON validation eagerly consumes the source. Trace it there, including
        // transport failures, and close before its buffered body is read again.
        if collectsJSON { response.body = trace.observing(response.body) }
        if streaming, wire == .responses, responsesProviderID != nil, (200..<300).contains(response.status.code) {
            response.body = trace.observingUpstream(response.body)
        }
        do {
            var validated = try await ProviderToolResponse.validated(
                response,
                requestBody: body,
                wire: wire,
                maximumBytes: maximumErrorBytes,
                declaredToolBindings: declaredToolBindings,
                toolNameCatalog: toolNameCatalog
            ) { bytes in
                if !collectsJSON { trace.append(bytes) }
            }
            if collectsJSON { trace.finish() }
            if wire == .responses, let responsesProviderID {
                validated = try await ResponsesProviderStateResponse.tagged(
                    validated, providerID: responsesProviderID, maximumBytes: maximumErrorBytes
                )
            }
            return GatewayModelExchange(response: validated, trace: trace)
        } catch {
            trace.finish()
            throw error
        }
    }
}
