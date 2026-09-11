import Foundation
import Hummingbird
import LittleSwitchSearch

extension GatewayResponder {
    package func admittedResponsesResponse(
        _ context: TransparentResponsesContext,
        prepared: PreparedGatewayResponses?,
        configuration: WebSearchConfiguration
    ) async throws -> Response {
        var prepared = prepared
        if prepared == nil {
            do {
                let recovered = try await recoverNativeCompaction(
                    body: context.body, incomingHeaders: context.incomingHeaders, eventID: context.eventID
                )
                prepared = try PreparedGatewayResponses(
                    body: recovered, target: context.target, configuration: configuration)
            } catch is CancellationError {
                throw CancellationError()
            } catch GatewayNativeCompactionRecoveryError.needsAuthentication {
                return openAIError(status: .unauthorized, message: CodexNativePassthrough.sentinelRejectionMessage)
            } catch let failure as CompactionUpstreamFailure {
                return bufferedResponse(failure.response, body: failure.body)
            } catch {
                return openAIError(status: .badGateway, message: "Could not recover the OpenAI conversation checkpoint")
            }
        }
        guard let prepared, prepared.body.count <= maximumRequestBytes else {
            return openAIError(status: .contentTooLarge, message: "Expanded history is too large")
        }
        var responder = self
        responder.responsesProviderID = context.target.provider.id
        if let compactionPlan = prepared.compaction {
            return try await responder.responsesCompactionResponse(
                plan: compactionPlan,
                target: .managed(context.target, credential: context.credential),
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
