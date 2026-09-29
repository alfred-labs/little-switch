import Foundation
import Hummingbird
import LittleSwitchCommon
import LittleSwitchSearch

extension GatewayResponder {
    package func admittedResponsesResponse(
        _ context: TransparentResponsesContext,
        prepared: PreparedGatewayResponses,
        configuration: WebSearchConfiguration
    ) async throws -> Response {
        guard prepared.body.count <= maximumRequestBytes else {
            return openAIError(status: .contentTooLarge, message: "Expanded history is too large")
        }
        var responder = self
        responder.responsesProviderID = context.target.provider.id
        let usesAdapter = await resolvesChatCompletionsAdapter(context.target.provider)
        let requiresFallback = usesAdapter || prepared.compaction != nil || prepared.webSearch != nil
        if requiresFallback {
            try await responsesWebSocketContext?.requireFallbackAllowed()
        }
        if let socket = responsesWebSocketContext, !socket.turn.generate, requiresFallback {
            let response = try ResponsesWebSocketExchangeContext.warmup(body: prepared.body)
            return streamingResponse(response.response, eventID: context.eventID, attempt: 0, errorStyle: .openAI)
        }
        if let compactionPlan = prepared.compaction {
            responder.responsesWebSocketContext = nil
            return try await responder.responsesCompactionResponse(
                plan: compactionPlan,
                target: GatewayCompactionTarget(route: context.target, credential: context.credential),
                incomingHeaders: context.incomingHeaders,
                eventID: context.eventID
            )
        }
        var searchResponder = responder
        searchResponder.responsesWebSocketContext = nil
        if let response = try await searchResponder.dispatchResponsesWebSearch(
            GatewayResponsesWebSearchAdmission(
                body: prepared.body,
                configuration: configuration,
                target: context.target,
                providerCredential: context.credential,
                incomingHeaders: context.incomingHeaders,
                eventID: context.eventID,
                prepared: prepared.webSearch
            )
        ) {
            return response
        }
        return try await responder.transparentResponsesResponse(
            TransparentResponsesContext(
                body: prepared.body,
                model: context.model,
                target: context.target,
                credential: context.credential,
                incomingHeaders: context.incomingHeaders,
                eventID: context.eventID,
                streaming: context.streaming
            )
        )
    }
}
