import AsyncHTTPClient
import Foundation
import Hummingbird
import NIOHTTP1

private struct DirectMessageContext {
    let body: Data
    let target: RoutedTarget
    let secret: String?
    let incomingHeaders: HTTPHeaders
    let eventID: UUID
    let streaming: Bool
}

private struct MessageRoutingMetadata {
    let target: RoutedTarget
    let streaming: Bool
}

extension GatewayResponder {
    package func messagesResponse(
        _ request: Request,
        eventID: UUID
    ) async throws -> Response {
        try Task.checkCancellation()
        let capture = try await dependencies.snapshotCapturer.capture(state: state)
        try Task.checkCancellation()
        let incomingBody: Data
        switch try await collect(request.body, errorStyle: .anthropic) {
        case .data(let value):
            incomingBody = value
        case .response(let response):
            return response
        }
        trafficRecorder.record(eventID: eventID, action: .claudeRequestBody(incomingBody))
        guard let metadata = messageRoutingMetadata(body: incomingBody, capture: capture) else {
            return anthropicError(status: .badRequest, message: "Unknown or invalid model mapping")
        }
        await GatewayMonitoringScope.current?.target(
            providerID: metadata.target.provider.id, model: metadata.target.modelID)
        let compatibleBody: Data
        let prepared: PreparedWebSearchRequest?
        do {
            compatibleBody = try AnthropicThinkingCompatibility.applying(
                metadata.target.provider.disabledThinkingOverride,
                to: incomingBody
            )
            prepared = try AnthropicWebSearch.prepare(
                body: compatibleBody,
                targetModel: metadata.target.modelID,
                configuration: capture.snapshot.webSearch
            )
        } catch {
            return anthropicError(status: .badRequest, message: "Invalid web search request")
        }
        let secret: String?
        do {
            secret = try await state.providerCredential(
                providerID: metadata.target.provider.id,
                capture: capture,
                secretStore: secretStore
            )
        } catch GatewayAdmissionError.invalidated {
            await GatewayMonitoringScope.current?.admission(.invalidated)
            throw HandledAdmissionFailure(style: .anthropic, kind: .queue)
        } catch {
            return anthropicError(
                status: .internalServerError,
                message: "Could not read provider credential"
            )
        }
        let incomingHeaders = nioHeaders(request.headers)
        trafficRecorder.record(
            eventID: eventID,
            action: .routed(
                trafficRoute(
                    client: .claude,
                    modelIdentifier: metadata.target.route.id,
                    target: metadata.target,
                    streaming: metadata.streaming
                )
            )
        )

        try Task.checkCancellation()
        try await admitRequest(
            GatewayRequestAdmission(
                eventID: eventID,
                capture: capture,
                client: .claude,
                modelIdentifier: metadata.target.route.id,
                providerID: metadata.target.provider.id,
                targetModelID: metadata.target.modelID,
                retainedBodyBytes: incomingBody.count
            ),
            errorStyle: .anthropic
        )
        try Task.checkCancellation()

        if let prepared {
            return try await webSearchResponse(
                context: GatewayWebSearchContext(
                    prepared: prepared,
                    configuration: capture.snapshot.webSearch,
                    target: metadata.target,
                    providerCredential: secret,
                    incomingHeaders: incomingHeaders,
                    eventID: eventID
                )
            )
        }

        return try await directMessageResponse(
            DirectMessageContext(
                body: compatibleBody,
                target: metadata.target,
                secret: secret,
                incomingHeaders: incomingHeaders,
                eventID: eventID,
                streaming: metadata.streaming
            )
        )
    }

    private func directMessageResponse(
        _ context: DirectMessageContext
    ) async throws -> Response {
        let upstreamBody: Data
        do {
            upstreamBody = try dependencies.serializer.rewriteMessage(
                context.body,
                modelID: context.target.modelID
            )
        } catch {
            return anthropicError(status: .badRequest, message: "Invalid message request")
        }

        let upstreamRequest: HTTPClientRequest
        do {
            upstreamRequest = try ProviderRequestBuilder.message(
                provider: context.target.provider,
                secret: context.secret,
                headers: context.incomingHeaders,
                body: upstreamBody
            )
        } catch {
            return anthropicError(status: .serviceUnavailable, message: "Provider is not ready")
        }
        try Task.checkCancellation()

        trafficRecorder.record(
            eventID: context.eventID,
            action: .upstreamRequest(
                trafficUpstreamRequest(
                    attempt: 0,
                    target: context.target,
                    request: upstreamRequest,
                    body: upstreamBody,
                    streaming: context.streaming
                )
            )
        )

        let firstResponse: GatewayModelExchange
        do {
            try Task.checkCancellation()
            firstResponse = try await executeModelRequest(
                upstreamRequest, body: upstreamBody, wire: .anthropic, eventID: context.eventID, attempt: 0
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch is ProviderToolContract.Error {
            return anthropicError(status: .badGateway, message: "Invalid provider response")
        } catch {
            return anthropicError(status: .badGateway, message: "Provider request failed")
        }
        try Task.checkCancellation()
        let response = try await providerResponse(
            firstResponse.response,
            context: MessageAttemptContext(
                eventID: context.eventID,
                target: context.target,
                secret: context.secret,
                incomingHeaders: context.incomingHeaders,
                upstreamBody: upstreamBody,
                streaming: context.streaming
            ),
            trace: firstResponse.trace
        )
        try Task.checkCancellation()
        return response
    }

    private func messageRoutingMetadata(
        body: Data,
        capture: GatewayRoutingCapture
    ) -> MessageRoutingMetadata? {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let model = root["model"] as? String,
            let target = capture.snapshot.resolve(model: model)
        else {
            return nil
        }
        return MessageRoutingMetadata(
            target: target,
            streaming: root["stream"] as? Bool ?? false
        )
    }

}
