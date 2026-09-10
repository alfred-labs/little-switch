import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchSearch
import NIOCore
import NIOHTTP1

package struct GatewayResponsesWebSearchContext {
    let prepared: PreparedResponsesWebSearchRequest
    let configuration: WebSearchConfiguration
    let target: CodexModelTarget
    let providerCredential: String?
    let searchCredential: String?
    let incomingHeaders: HTTPHeaders
    let eventID: UUID
    var needsChatCompletionsAdapter: Bool

    package init(
        prepared: PreparedResponsesWebSearchRequest,
        configuration: WebSearchConfiguration,
        target: CodexModelTarget,
        providerCredential: String?,
        searchCredential: String?,
        incomingHeaders: HTTPHeaders,
        eventID: UUID,
        needsChatCompletionsAdapter: Bool
    ) {
        self.prepared = prepared
        self.configuration = configuration
        self.target = target
        self.providerCredential = providerCredential
        self.searchCredential = searchCredential
        self.incomingHeaders = incomingHeaders
        self.eventID = eventID
        self.needsChatCompletionsAdapter = needsChatCompletionsAdapter
    }

    /// The same dispatch on the chat-completions adapter. Used when a native
    /// first turn proves the provider has no `/v1/responses`: the adapted
    /// context never falls back again (its wire is already the fallback).
    package func usingChatCompletionsAdapter() -> GatewayResponsesWebSearchContext {
        var copy = self
        copy.needsChatCompletionsAdapter = true
        return copy
    }
}

package struct GatewayResponsesWebSearchAdmission {
    let body: Data
    let configuration: WebSearchConfiguration
    let target: CodexModelTarget
    let providerCredential: String?
    let incomingHeaders: HTTPHeaders
    let eventID: UUID
    /// The prepare run during admission validation, threaded forward so the
    /// dispatch does not re-parse and re-adapt the same body.
    let prepared: PreparedResponsesWebSearchRequest?

    package init(
        body: Data,
        configuration: WebSearchConfiguration,
        target: CodexModelTarget,
        providerCredential: String?,
        incomingHeaders: HTTPHeaders,
        eventID: UUID,
        prepared: PreparedResponsesWebSearchRequest? = nil
    ) {
        self.body = body
        self.configuration = configuration
        self.target = target
        self.providerCredential = providerCredential
        self.incomingHeaders = incomingHeaders
        self.eventID = eventID
        self.prepared = prepared
    }
}

package enum GatewayResponsesWebSearchError: Swift.Error {
    case providerNotReady
    case providerFailed
    case invalidProviderResponse
    case invalidProviderRequest(String)
    case requestTooLarge
    case generatedRequestTooLarge
    case responseTooLarge
}

private struct BufferedResponsesModelTurn {
    let response: HTTPClientResponse
    let body: Data
}

package struct ResponsesModelTurnRequest {
    let body: Data
    let attempt: Int
    let context: GatewayResponsesWebSearchContext
}

package struct PreparedResponsesModelRequest {
    let request: HTTPClientRequest
    let adapted: PreparedResponsesChatCompletionsRequest?
    let body: Data
}

private struct ResponsesWebSearchLoopState {
    var upstreamBody: Data
    var modelAttempt = 0
    var successfulSearches = 0
    var forceFinalTurn = false
    var traces: [ResponsesWebSearchTrace] = []
    var usage = ResponsesUsage(inputTokens: 0, outputTokens: 0)

    mutating func nextSearchID(turnID: String) -> String {
        let base = turnID.hasPrefix("resp_") ? String(turnID.dropFirst(5)) : turnID
        return "ws_\(base)_\(traces.count + 1)"
    }
}

extension GatewayResponder {
    package func dispatchResponsesWebSearch(
        _ admission: GatewayResponsesWebSearchAdmission
    ) async throws -> Response? {
        let prepared =
            try admission.prepared
            ?? OpenAIResponsesWebSearch.prepare(
                body: admission.body,
                targetModel: admission.target.model.id,
                configuration: admission.configuration
            )
        guard let prepared else {
            return nil
        }

        let searchCredential: String?
        do {
            searchCredential =
                prepared.maximumUses > 0
                ? try webSearchCredential(for: admission.configuration) : nil
        } catch {
            return openAIError(
                status: .internalServerError,
                message: "Could not read web search credential"
            )
        }
        let needsChatCompletionsAdapter = await resolvesChatCompletionsAdapter(
            admission.target.provider
        )
        return try await responsesWebSearchResponse(
            context: GatewayResponsesWebSearchContext(
                prepared: prepared,
                configuration: admission.configuration,
                target: admission.target,
                providerCredential: admission.providerCredential,
                searchCredential: searchCredential,
                incomingHeaders: admission.incomingHeaders,
                eventID: admission.eventID,
                needsChatCompletionsAdapter: needsChatCompletionsAdapter
            )
        )
    }

    package func responsesWebSearchResponse(
        context: GatewayResponsesWebSearchContext
    ) async throws -> Response {
        try Task.checkCancellation()
        switch responsesWebSearchPreflight(context: context) {
        case .ready:
            break
        case .rejected(let response):
            return response
        }
        try Task.checkCancellation()
        if context.prepared.streaming {
            return try await liveResponsesWebSearchResponse(context: context)
        }

        return try await bufferedResponsesWebSearchResponse(context: context)
    }

    private func bufferedResponsesWebSearchResponse(
        context: GatewayResponsesWebSearchContext,
        attemptOffset: Int = 0
    ) async throws -> Response {
        var loop = ResponsesWebSearchLoopState(upstreamBody: context.prepared.upstreamBody)
        let result: Response
        responseLoop: while true {
            try Task.checkCancellation()
            let buffered: BufferedResponsesModelTurn
            do {
                buffered = try await executeResponsesModelTurn(
                    ResponsesModelTurnRequest(
                        body: loop.upstreamBody,
                        attempt: attemptOffset + loop.modelAttempt,
                        context: context
                    )
                )
                try Task.checkCancellation()
            } catch is CancellationError {
                throw CancellationError()
            } catch GatewayResponsesWebSearchError.invalidProviderResponse {
                result = openAIError(status: .badGateway, message: "Invalid provider response")
                break responseLoop
            } catch {
                result = openAIError(status: .badGateway, message: "Provider request failed")
                break responseLoop
            }

            guard (200..<300).contains(buffered.response.status.code) else {
                let nativeProbeFailed =
                    loop.modelAttempt == 0
                    && !context.needsChatCompletionsAdapter
                    && responsesAdapterFallbackApplies(
                        status: UInt(buffered.response.status.code),
                        provider: context.target.provider
                    )
                if nativeProbeFailed {
                    // The native first turn proved the provider has no
                    // /v1/responses; the ledger just learned it, so retry this
                    // request on the adapter instead of relaying the 404. The
                    // retry records under its own attempt so the traffic log
                    // keeps both exchanges.
                    return try await bufferedResponsesWebSearchResponse(
                        context: context.usingChatCompletionsAdapter(),
                        attemptOffset: 1
                    )
                }
                if loop.modelAttempt == 0 {
                    result = bufferedResponse(buffered.response, body: buffered.body)
                } else {
                    result = openAIError(status: .badGateway, message: "Provider follow-up failed")
                }
                break responseLoop
            }

            let turn: ResponsesModelTurn
            do {
                turn = try OpenAIResponsesWebSearch.parseModelTurn(
                    buffered.body, privateToolName: context.prepared.privateToolName
                )
            } catch {
                result = openAIError(status: .badGateway, message: "Invalid provider response")
                break responseLoop
            }
            loop.usage.add(turn.usage)

            guard !loop.forceFinalTurn, let toolCall = turn.webSearchCall else {
                result = projectedResponsesWebSearchResponse(
                    prepared: context.prepared,
                    traces: loop.traces,
                    finalTurn: turn,
                    usage: loop.usage
                )
                break responseLoop
            }

            do {
                try await advanceResponsesWebSearch(
                    state: &loop,
                    turn: turn,
                    toolCall: toolCall,
                    context: context
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                result = openAIError(status: .badGateway, message: "Invalid provider response")
                break responseLoop
            }
            loop.modelAttempt += 1
        }
        return result
    }

    private func advanceResponsesWebSearch(
        state: inout ResponsesWebSearchLoopState,
        turn: ResponsesModelTurn,
        toolCall: ResponsesWebSearchToolCall,
        context: GatewayResponsesWebSearchContext
    ) async throws {
        let searchID = state.nextSearchID(turnID: turn.id)
        state.traces.append(
            ResponsesWebSearchTrace(
                id: searchID,
                callID: toolCall.callID,
                query: toolCall.query,
                outputJSON: turn.outputJSON
            )
        )
        let outcome = try await admittedWebSearch(
            WebSearchAttemptRequest(
                rawQuery: toolCall.query,
                options: context.prepared.searchOptions,
                successfulSearches: state.successfulSearches,
                maximumUses: context.prepared.maximumUses
            ),
            configuration: context.configuration,
            credential: context.searchCredential,
            eventID: context.eventID
        )
        let results: [WebSearchResult]
        switch outcome {
        case .invalidRequest:
            try forceFinalResponsesTurn(
                state: &state,
                turn: turn,
                toolCall: toolCall,
                errorCode: "invalid_request"
            )
            return
        case .overBudget:
            try forceFinalResponsesTurn(
                state: &state,
                turn: turn,
                toolCall: toolCall,
                errorCode: "max_uses_exceeded"
            )
            return
        case .unavailable:
            try forceFinalResponsesTurn(
                state: &state,
                turn: turn,
                toolCall: toolCall,
                errorCode: "unavailable"
            )
            return
        case .results(let found):
            results = found
        }

        state.traces[state.traces.count - 1].sources = results.map(\.url)
        state.upstreamBody = try OpenAIResponsesWebSearch.followUpRequest(
            baseBody: state.upstreamBody,
            turn: turn,
            toolCall: toolCall,
            resultText: AnthropicWebSearch.formatResults(results),
            mode: .result
        )
        state.successfulSearches += 1
    }

    private func forceFinalResponsesTurn(
        state: inout ResponsesWebSearchLoopState,
        turn: ResponsesModelTurn,
        toolCall: ResponsesWebSearchToolCall,
        errorCode: String
    ) throws {
        state.traces[state.traces.count - 1].failed = true
        state.upstreamBody = try OpenAIResponsesWebSearch.followUpRequest(
            baseBody: state.upstreamBody,
            turn: turn,
            toolCall: toolCall,
            resultText: errorCode,
            mode: .terminalError
        )
        state.forceFinalTurn = true
    }

    private func executeResponsesModelTurn(
        _ turnRequest: ResponsesModelTurnRequest
    ) async throws -> BufferedResponsesModelTurn {
        guard turnRequest.body.count <= maximumRequestBytes else {
            throw GatewayResponsesWebSearchError.requestTooLarge
        }
        let context = turnRequest.context
        let preparation = try responsesModelRequest(turnRequest)
        let adapted = preparation.adapted
        let requestBody = preparation.body
        let request = preparation.request
        trafficRecorder.record(
            eventID: context.eventID,
            action: .upstreamRequest(
                trafficUpstreamRequest(
                    attempt: turnRequest.attempt,
                    route: ResponsesTrafficRoute(
                        claudeRoute: context.prepared.originalModel,
                        target: context.target
                    ),
                    request: request,
                    body: requestBody,
                    streaming: false
                )
            )
        )

        let exchange: GatewayModelExchange
        do {
            try Task.checkCancellation()
            exchange = try await executeModelRequest(
                request,
                body: requestBody,
                wire: context.needsChatCompletionsAdapter ? .chatCompletions : .responses,
                eventID: context.eventID,
                attempt: turnRequest.attempt,
                declaredToolBindings: adapted?.declaredToolBindings ?? context.prepared.declaredToolBindings
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

        let responseBody: Data
        do {
            try Task.checkCancellation()
            responseBody = try await exchange.trace.collect(response.body, upTo: maximumErrorBytes)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch is NIOTooManyBytesError {
            throw GatewayResponsesWebSearchError.responseTooLarge
        } catch {
            throw GatewayResponsesWebSearchError.providerFailed
        }
        guard let adapted, (200..<300).contains(response.status.code) else {
            return BufferedResponsesModelTurn(response: response, body: responseBody)
        }
        do {
            return BufferedResponsesModelTurn(
                response: response,
                body: try OpenAIResponsesChatCompletions.project(
                    responseBody: responseBody,
                    prepared: adapted
                )
            )
        } catch {
            throw GatewayResponsesWebSearchError.invalidProviderResponse
        }
    }

    private func projectedResponsesWebSearchResponse(
        prepared: PreparedResponsesWebSearchRequest,
        traces: [ResponsesWebSearchTrace],
        finalTurn: ResponsesModelTurn,
        usage: ResponsesUsage
    ) -> Response {
        let body: Data
        do {
            body = try dependencies.projector.responsesResponse(
                prepared: prepared,
                traces: traces,
                finalTurn: finalTurn,
                usage: usage
            )
        } catch {
            return openAIError(status: .badGateway, message: "Could not project provider response")
        }

        let headers: HTTPFields = [.contentType: "application/json"]
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: body))
        )
    }
}
