import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOHTTP1

extension GatewayResponder {
    package func compactionModelTurn(
        body: Data,
        target: GatewayCompactionTarget,
        incomingHeaders: HTTPHeaders,
        eventID: UUID,
        attempt: Int,
        preferredWire: ProviderResponsesWireOverride? = nil
    ) async throws -> ResponsesModelTurn {
        let adapted: PreparedResponsesChatCompletionsRequest?
        let request: HTTPClientRequest
        let wire: ProviderToolContract.Wire
        let upstreamBody: Data
        let route = target.route
        let usesChat =
            preferredWire == .chatCompletions ? true : await resolvesChatCompletionsAdapter(route.provider)
        if usesChat {
            let prepared = try OpenAIResponsesChatCompletions.prepare(
                body: body, targetModel: route.model.id, providerID: route.provider.id)
            adapted = prepared
            upstreamBody = prepared.upstreamBody
            wire = .chatCompletions
            request = try ProviderRequestBuilder.chatCompletions(
                provider: route.provider, secret: target.credential, headers: incomingHeaders, body: upstreamBody
            )
        } else {
            adapted = nil
            upstreamBody = try ResponsesChatCompletionsReasoning.nativeRequestBody(
                OpenAIResponsesNativeNamespacing.normalize(body).body, providerID: route.provider.id)
            wire = .responses
            request = try ProviderRequestBuilder.responses(
                provider: route.provider, secret: target.credential, headers: incomingHeaders, body: upstreamBody
            )
        }
        trafficRecorder.record(
            eventID: eventID,
            action: .upstreamRequest(
                trafficUpstreamRequest(
                    attempt: attempt,
                    route: ResponsesTrafficRoute(
                        claudeRoute: route.provider.reference(to: route.model.id), target: route),
                    request: request,
                    body: upstreamBody,
                    streaming: false
                )
            )
        )
        guard upstreamBody.count <= maximumRequestBytes else { throw ResponsesCompactionError.invalidRequest }
        let exchange = try await executeModelRequest(
            request,
            body: upstreamBody,
            wire: wire,
            eventID: eventID,
            attempt: attempt,
            declaredToolBindings: adapted?.declaredToolBindings ?? [:],
            toolNameCatalog: adapted?.toolNameCatalog
        )
        let status = UInt(exchange.response.status.code)
        if adapted != nil {
            await recordChatCompletionsRouteAbsent(providerID: route.provider.id, status: status)
        } else {
            await recordResponsesCapability(providerID: route.provider.id, status: status)
            if responsesAdapterFallbackApplies(status: status, provider: route.provider) {
                _ = try? await exchange.trace.collect(exchange.response.body, upTo: maximumErrorBytes)
                return try await compactionModelTurn(
                    body: body,
                    target: target,
                    incomingHeaders: incomingHeaders,
                    eventID: eventID,
                    attempt: attempt + 1,
                    preferredWire: .chatCompletions
                )
            }
        }
        let turn = try await collectCompactionTurn(exchange, adapted: adapted)
        let root = try ResponsesCompactionJSON.object(turn.rootJSON, error: .invalidResponse)
        // Only a completed model turn may reach selection repair; a terminal
        // interruption has the same outcome whether it arrived as JSON or SSE.
        guard try OpenAIResponsesWebSearch.modelTerminalStatus(from: root) == .completed else {
            throw ResponsesCompactionError.invalidResponse
        }
        return turn
    }

    private func collectCompactionTurn(
        _ exchange: GatewayModelExchange,
        adapted: PreparedResponsesChatCompletionsRequest?
    ) async throws -> ResponsesModelTurn {
        let response = exchange.response
        guard (200..<300).contains(response.status.code) else {
            let bytes: Data
            do {
                bytes = try await exchange.trace.collect(response.body, upTo: maximumErrorBytes)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw CompactionUpstreamFailure(response: response, body: Data())
            }
            throw CompactionUpstreamFailure(response: response, body: bytes)
        }
        if response.headers["content-type"].contains(where: { $0.lowercased().contains("text/event-stream") }) {
            defer { exchange.trace.finish() }
            var decoder = ServerSentEventDecoder(maximumFrameBytes: maximumErrorBytes)
            var native = OpenAIResponsesTurnAccumulator(maximumTurnBytes: maximumErrorBytes, privateToolName: nil)
            var chat = adapted.map {
                OpenAIChatCompletionsAccumulator(prepared: $0, maximumTurnBytes: maximumErrorBytes)
            }
            for try await buffer in response.body {
                try Task.checkCancellation()
                exchange.trace.append(Data(buffer.readableBytesView))
                for frame in try decoder.append(buffer) {
                    if chat != nil { _ = try chat?.consume(frame) } else { _ = try native.consume(frame) }
                }
            }
            for frame in try decoder.finish() {
                if chat != nil { _ = try chat?.consume(frame) } else { _ = try native.consume(frame) }
            }
            if var chat { return try chat.finish() }
            return try native.finish()
        }
        let bytes = try await exchange.trace.collect(response.body, upTo: maximumErrorBytes)
        try Task.checkCancellation()
        let projected =
            try adapted.map { try OpenAIResponsesChatCompletions.project(responseBody: bytes, prepared: $0) } ?? bytes
        return try OpenAIResponsesWebSearch.parseModelTurn(projected, privateToolName: nil)
    }
}
