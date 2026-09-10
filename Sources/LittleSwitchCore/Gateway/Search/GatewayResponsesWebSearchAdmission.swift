import AsyncHTTPClient
import Foundation
import Hummingbird

package enum GatewayResponsesWebSearchPreflight {
    case ready(retainedUpstreamBytes: Int)
    case rejected(Response)
}

extension GatewayResponder {
    package func responsesWebSearchPreflight(
        context: GatewayResponsesWebSearchContext
    ) -> GatewayResponsesWebSearchPreflight {
        do {
            let retainedBytes = try validatedResponsesWebSearchBytes(context: context)
            return .ready(retainedUpstreamBytes: retainedBytes)
        } catch {
            trafficRecorder.record(
                eventID: context.eventID,
                action: .failed(
                    TrafficFailureCompletion(
                        status: nil,
                        finishedAt: Date(),
                        failure: TrafficFailure(
                            kind: "preflight",
                            message: String(describing: error)
                        )
                    )
                )
            )
            return .rejected(responsesWebSearchPreflightFailureResponse(for: error))
        }
    }

    package func responsesModelRequest(
        _ turnRequest: ResponsesModelTurnRequest
    ) throws -> PreparedResponsesModelRequest {
        let context = turnRequest.context
        let adapted: PreparedResponsesChatCompletionsRequest?
        let requestBody: Data
        let request: HTTPClientRequest
        let needsAdapter = context.needsChatCompletionsAdapter
        if needsAdapter {
            do {
                let prepared = try OpenAIResponsesChatCompletions.prepare(
                    body: turnRequest.body,
                    targetModel: context.target.model.id,
                    inheritedToolBindings: context.prepared.toolBindings,
                    inheritedToolSearchContract: context.prepared.toolSearchContract
                )
                adapted = prepared
                requestBody = prepared.upstreamBody
            } catch {
                throw GatewayResponsesWebSearchError.invalidProviderRequest(
                    String(describing: error)
                )
            }
        } else {
            adapted = nil
            requestBody = turnRequest.body
        }
        do {
            request = try responsesProviderRequest(
                needsAdapter: needsAdapter,
                context: context,
                body: requestBody
            )
        } catch {
            throw GatewayResponsesWebSearchError.providerNotReady
        }
        guard requestBody.count <= maximumRequestBytes else {
            throw GatewayResponsesWebSearchError.generatedRequestTooLarge
        }
        return PreparedResponsesModelRequest(
            request: request,
            adapted: adapted,
            body: requestBody
        )
    }

    private func validatedResponsesWebSearchBytes(
        context: GatewayResponsesWebSearchContext
    ) throws -> Int {
        guard context.prepared.upstreamBody.count <= maximumRequestBytes else {
            throw GatewayResponsesWebSearchError.requestTooLarge
        }
        let bodyCount: Int
        if context.prepared.streaming {
            let live = try responsesLiveModelRequest(
                body: context.prepared.upstreamBody,
                context: context
            )
            recordDroppedAgentMail(
                context: context,
                adaptedCount: live.adapted?.droppedMailCount ?? 0
            )
            bodyCount = live.body.count
        } else {
            let model = try responsesModelRequest(
                ResponsesModelTurnRequest(
                    body: context.prepared.upstreamBody,
                    attempt: 0,
                    context: context
                )
            )
            recordDroppedAgentMail(
                context: context,
                adaptedCount: model.adapted?.droppedMailCount ?? 0
            )
            bodyCount = model.body.count
        }
        guard bodyCount <= maximumRequestBytes else {
            throw GatewayResponsesWebSearchError.generatedRequestTooLarge
        }
        return bodyCount
    }

    /// Unparseable inter-agent mail cannot be converted nor forwarded; the
    /// rewrite layers drop it and count it. Surface the count in the traffic
    /// log so the next empty-brief variant announces itself. An annotation,
    /// not a failure: preflight passing must not poison the request's
    /// eventual outcome or fold usage a second time.
    private func recordDroppedAgentMail(
        context: GatewayResponsesWebSearchContext,
        adaptedCount: Int
    ) {
        let total = context.prepared.droppedMailCount + adaptedCount
        guard total > 0 else {
            return
        }
        trafficRecorder.record(
            eventID: context.eventID,
            action: .annotation(
                TrafficAnnotation(
                    kind: "agent-mail",
                    message: "Dropped \(total) unparseable agent message(s)"
                )
            )
        )
    }

    package func responsesProviderRequest(
        needsAdapter: Bool,
        context: GatewayResponsesWebSearchContext,
        body: Data
    ) throws -> HTTPClientRequest {
        if needsAdapter {
            return try ProviderRequestBuilder.chatCompletions(
                provider: context.target.provider,
                secret: context.providerCredential,
                headers: context.incomingHeaders,
                body: body
            )
        }
        return try ProviderRequestBuilder.responses(
            provider: context.target.provider,
            secret: context.providerCredential,
            headers: context.incomingHeaders,
            body: body
        )
    }
}

package func responsesWebSearchPreflightFailureResponse(
    for error: any Error
) -> Response {
    if let error = error as? GatewayResponsesWebSearchError {
        switch error {
        case .providerNotReady:
            return openAIError(status: .serviceUnavailable, message: "Provider is not ready")
        case .requestTooLarge:
            return openAIError(status: .contentTooLarge, message: "Request body is too large")
        case .providerFailed, .generatedRequestTooLarge:
            return openAIError(status: .badGateway, message: "Provider request failed")
        case .invalidProviderResponse, .invalidProviderRequest, .responseTooLarge:
            return openAIError(status: .badGateway, message: "Invalid provider response")
        }
    }
    if let error = error as? GatewayResponsesLiveError {
        switch error {
        case .providerNotReady:
            return openAIError(status: .serviceUnavailable, message: "Provider is not ready")
        case .requestTooLarge:
            return openAIError(status: .contentTooLarge, message: "Request body is too large")
        case .providerFailed:
            return openAIError(status: .badGateway, message: "Provider request failed")
        case .invalidProviderResponse, .invalidProviderRequest, .invalidProviderStream,
            .clientWriteFailed, .providerTerminalFailed:
            return openAIError(status: .badGateway, message: "Invalid provider response")
        }
    }
    return openAIError(status: .badGateway, message: "Invalid provider request")
}
