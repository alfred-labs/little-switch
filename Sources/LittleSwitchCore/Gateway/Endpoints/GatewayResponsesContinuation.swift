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
        if let compactionPlan = prepared.compaction {
            return try await responder.responsesCompactionResponse(
                plan: compactionPlan,
                target: GatewayCompactionTarget(route: context.target, credential: context.credential),
                incomingHeaders: context.incomingHeaders,
                eventID: context.eventID
            )
        }
        if let response = try await responder.dispatchResponsesWebSearch(
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
