import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import NIOCore

struct BufferedResponsesModelTurn {
    let response: HTTPClientResponse
    let body: Data
    let nextAttempt: Int
    let imageFallbackUsed: Bool
}

extension GatewayResponder {
    func executeResponsesModelTurn(
        _ turnRequest: ResponsesModelTurnRequest,
        forceText: Bool = false
    ) async throws -> BufferedResponsesModelTurn {
        guard turnRequest.body.count <= maximumRequestBytes else {
            throw GatewayResponsesWebSearchError.requestTooLarge
        }
        let context = turnRequest.context
        let wire: ModelImageInputWire = context.needsChatCompletionsAdapter ? .chatCompletions : .responses
        let projected = try await responsesImageInput(
            body: turnRequest.body, target: context.target, wire: wire, forceText: forceText)
        let preparation = try responsesModelRequest(
            ResponsesModelTurnRequest(
                body: projected.body, attempt: turnRequest.attempt, context: context))
        let adapted = preparation.adapted
        let requestBody = preparation.body
        let request = preparation.request
        let upstreamTraffic = trafficUpstreamRequest(
            attempt: turnRequest.attempt,
            route: ResponsesTrafficRoute(
                claudeRoute: context.prepared.originalModel,
                target: context.target
            ),
            request: request,
            body: requestBody,
            streaming: false
        )

        let exchange: GatewayModelExchange
        do {
            try Task.checkCancellation()
            exchange = try await executeModelRequest(
                request,
                body: requestBody,
                traffic: upstreamTraffic,
                wire: context.needsChatCompletionsAdapter ? .chatCompletions : .responses,
                eventID: context.eventID,
                attempt: turnRequest.attempt,
                declaredToolBindings: adapted?.declaredToolBindings ?? context.prepared.declaredToolBindings,
                toolNameCatalog: adapted?.toolNameCatalog ?? context.prepared.toolNameCatalog
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch is ProviderToolContract.Error {
            throw GatewayResponsesWebSearchError.invalidProviderResponse
        } catch {
            throw GatewayResponsesWebSearchError.providerFailed
        }
        let response = exchange.response
        defer { exchange.trace.finish() }
        await recordResponsesCapability(context: context, status: response.status.code)
        // The adapter's own route missing is the mirror lesson: only native
        // can be left, so a stale adapter verdict relearns instead of
        // relaying the 404 forever.
        if context.needsChatCompletionsAdapter {
            await recordChatCompletionsRouteAbsent(
                providerID: context.target.provider.id,
                status: response.status.code
            )
        }

        let responseBody = try await collectSearchModelTurn(exchange)
        let sentImages = !projected.imageItemIndices.isEmpty && projected.omittedImageCount == 0
        let rejected = await learnResponsesImageRejection(
            status: response.status.code,
            body: responseBody,
            target: context.target,
            wire: wire,
            hasImageInput: sentImages)
        if rejected && !forceText {
            return try await executeResponsesModelTurn(
                ResponsesModelTurnRequest(body: turnRequest.body, attempt: turnRequest.attempt + 1, context: context),
                forceText: true)
        }
        guard let adapted, (200..<300).contains(response.status.code) else {
            return BufferedResponsesModelTurn(
                response: response,
                body: responseBody,
                nextAttempt: turnRequest.attempt + 1,
                imageFallbackUsed: forceText)
        }
        do {
            return BufferedResponsesModelTurn(
                response: response,
                body: try OpenAIResponsesChatCompletions.project(
                    responseBody: responseBody,
                    prepared: adapted
                ),
                nextAttempt: turnRequest.attempt + 1,
                imageFallbackUsed: forceText
            )
        } catch {
            throw GatewayResponsesWebSearchError.invalidProviderResponse
        }
    }

    private func collectSearchModelTurn(_ exchange: GatewayModelExchange) async throws -> Data {
        do {
            try Task.checkCancellation()
            let body = try await exchange.trace.collect(exchange.response.body, upTo: maximumErrorBytes)
            try Task.checkCancellation()
            return body
        } catch is CancellationError {
            throw CancellationError()
        } catch is NIOTooManyBytesError {
            throw GatewayResponsesWebSearchError.responseTooLarge
        } catch {
            throw GatewayResponsesWebSearchError.providerFailed
        }
    }
}
