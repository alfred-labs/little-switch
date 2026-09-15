import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchCommon
import LittleSwitchSearch
import NIOCore
import NIOHTTP1

package struct GatewayWebSearchContext: Sendable {
    let prepared: PreparedWebSearchRequest
    let configuration: WebSearchConfiguration
    let target: RoutedTarget
    let providerCredential: String?
    let incomingHeaders: HTTPHeaders
    let eventID: UUID
    let searchCredential: String?

    package init(
        prepared: PreparedWebSearchRequest,
        configuration: WebSearchConfiguration,
        target: RoutedTarget,
        providerCredential: String?,
        incomingHeaders: HTTPHeaders,
        eventID: UUID,
        searchCredential: String? = nil
    ) {
        self.prepared = prepared
        self.configuration = configuration
        self.target = target
        self.providerCredential = providerCredential
        self.incomingHeaders = incomingHeaders
        self.eventID = eventID
        self.searchCredential = searchCredential
    }
}

private enum GatewayWebSearchError: Swift.Error {
    case providerFailed
    case invalidProviderResponse
    case requestTooLarge
    case responseTooLarge
}

private struct BufferedModelTurn {
    let response: HTTPClientResponse
    let body: Data
}

private struct WebSearchModelTurnRequest {
    let body: Data
    let attempt: Int
    let target: RoutedTarget
    let credential: String?
    let incomingHeaders: HTTPHeaders
    let eventID: UUID
}

private struct WebSearchLoopState {
    var upstreamBody: Data
    let searchOptions: WebSearchFilterOptions
    let privateToolName: String?
    let eventID: UUID
    var modelAttempt = 0
    var successfulSearches = 0
    var forceFinalTurn = false
    var traces: [WebSearchTrace] = []
    var usage = AnthropicUsage(inputTokens: 0, outputTokens: 0)
    private var serverToolIDs: AnthropicServerToolIDSequence

    init(upstreamBody: Data, searchOptions: WebSearchFilterOptions, privateToolName: String?, eventID: UUID) {
        self.upstreamBody = upstreamBody
        self.searchOptions = searchOptions
        self.privateToolName = privateToolName
        self.eventID = eventID
        serverToolIDs = AnthropicServerToolIDSequence(eventID: eventID)
    }

    mutating func nextServerToolID() -> String {
        serverToolIDs.next()
    }
}

extension GatewayResponder {
    package func webSearchResponse(
        context: GatewayWebSearchContext
    ) async throws -> Response {
        try Task.checkCancellation()
        let searchCredential: String?
        switch webSearchPreflight(context: context) {
        case .ready(let credential):
            searchCredential = credential
        case .rejected(let response):
            return response
        }
        try Task.checkCancellation()

        if context.prepared.streaming {
            return try await liveWebSearchResponse(
                context: context,
                searchCredential: searchCredential
            )
        }

        return try await bufferedWebSearchResponse(
            context: context,
            searchCredential: searchCredential
        )
    }

    private func bufferedWebSearchResponse(
        context: GatewayWebSearchContext,
        searchCredential: String?
    ) async throws -> Response {
        var effectiveSearchConfiguration = context.configuration
        effectiveSearchConfiguration.maximumUses = context.prepared.maximumUses
        var loop = WebSearchLoopState(
            upstreamBody: context.prepared.upstreamBody,
            searchOptions: context.prepared.searchOptions,
            privateToolName: context.prepared.privateToolName,
            eventID: context.eventID
        )
        let result: Response
        responseLoop: while true {
            try Task.checkCancellation()
            let buffered: BufferedModelTurn
            do {
                buffered = try await executeWebSearchModelTurn(
                    WebSearchModelTurnRequest(
                        body: loop.upstreamBody,
                        attempt: loop.modelAttempt,
                        target: context.target,
                        credential: context.providerCredential,
                        incomingHeaders: context.incomingHeaders,
                        eventID: context.eventID
                    )
                )
                try Task.checkCancellation()
            } catch is CancellationError {
                throw CancellationError()
            } catch GatewayWebSearchError.invalidProviderResponse {
                result = anthropicError(status: .badGateway, message: "Invalid provider response")
                break responseLoop
            } catch {
                result = anthropicError(status: .badGateway, message: "Provider request failed")
                break responseLoop
            }

            guard (200..<300).contains(buffered.response.status.code) else {
                if loop.modelAttempt == 0 {
                    result = bufferedResponse(buffered.response, body: buffered.body)
                } else {
                    result = anthropicError(status: .badGateway, message: "Provider follow-up failed")
                }
                break responseLoop
            }

            let turn: AnthropicModelTurn
            do {
                turn = try AnthropicWebSearch.parseModelTurn(
                    buffered.body, privateToolName: context.prepared.privateToolName
                )
            } catch {
                result = anthropicError(status: .badGateway, message: "Invalid provider response")
                break responseLoop
            }
            loop.usage.add(turn.usage)

            guard !loop.forceFinalTurn, let toolCall = turn.webSearchCall else {
                result = projectedWebSearchResponse(
                    prepared: context.prepared,
                    traces: loop.traces,
                    finalTurn: turn,
                    usage: loop.usage
                )
                break responseLoop
            }

            do {
                try await advanceWebSearch(
                    state: &loop,
                    turn: turn,
                    toolCall: toolCall,
                    configuration: effectiveSearchConfiguration,
                    credential: searchCredential
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                result = anthropicError(status: .badGateway, message: "Invalid provider response")
                break responseLoop
            }
            loop.modelAttempt += 1
        }
        return result
    }

    private func advanceWebSearch(
        state: inout WebSearchLoopState,
        turn: AnthropicModelTurn,
        toolCall: WebSearchToolCall,
        configuration: WebSearchConfiguration,
        credential: String?
    ) async throws {
        let serverToolID = state.nextServerToolID()
        let outcome = try await admittedWebSearch(
            WebSearchAttemptRequest(
                rawQuery: toolCall.query,
                options: state.searchOptions,
                successfulSearches: state.successfulSearches,
                maximumUses: configuration.maximumUses
            ),
            configuration: configuration,
            credential: credential,
            eventID: state.eventID
        )
        let results: [WebSearchResult]
        switch outcome {
        case .invalidRequest:
            try forceFinalSearch(
                state: &state,
                turn: turn,
                toolCall: toolCall,
                serverToolID: serverToolID,
                errorCode: "invalid_request"
            )
            return
        case .overBudget:
            try forceFinalSearch(
                state: &state,
                turn: turn,
                toolCall: toolCall,
                serverToolID: serverToolID,
                errorCode: "max_uses_exceeded"
            )
            return
        case .unavailable:
            try forceFinalSearch(
                state: &state,
                turn: turn,
                toolCall: toolCall,
                serverToolID: serverToolID,
                errorCode: "unavailable"
            )
            return
        case .results(let found):
            results = found
        }

        state.traces.append(
            WebSearchTrace(
                toolUseID: serverToolID,
                query: toolCall.query,
                content: .results(results),
                publicContentJSON: turn.contentJSON
            )
        )
        state.upstreamBody = try AnthropicWebSearch.followUpRequest(
            baseBody: state.upstreamBody,
            turn: turn,
            toolCall: toolCall,
            resultText: AnthropicWebSearch.formatResults(results),
            mode: .result,
            privateToolName: state.privateToolName
        )
        state.successfulSearches += 1
    }

    private func forceFinalSearch(
        state: inout WebSearchLoopState,
        turn: AnthropicModelTurn,
        toolCall: WebSearchToolCall,
        serverToolID: String,
        errorCode: String
    ) throws {
        state.traces.append(
            WebSearchTrace(
                toolUseID: serverToolID,
                query: toolCall.query,
                content: .error(errorCode),
                publicContentJSON: turn.contentJSON
            )
        )
        state.upstreamBody = try AnthropicWebSearch.followUpRequest(
            baseBody: state.upstreamBody,
            turn: turn,
            toolCall: toolCall,
            resultText: errorCode,
            mode: .terminalError,
            privateToolName: state.privateToolName
        )
        state.forceFinalTurn = true
    }

    private func executeWebSearchModelTurn(
        _ turnRequest: WebSearchModelTurnRequest
    ) async throws -> BufferedModelTurn {
        guard turnRequest.body.count <= maximumRequestBytes else {
            throw GatewayWebSearchError.requestTooLarge
        }
        let request = try ProviderRequestBuilder.message(
            provider: turnRequest.target.provider,
            secret: turnRequest.credential,
            headers: turnRequest.incomingHeaders,
            body: turnRequest.body
        )
        let upstreamTraffic = trafficUpstreamRequest(
            attempt: turnRequest.attempt,
            target: turnRequest.target,
            request: request,
            body: turnRequest.body,
            streaming: false
        )

        let exchange: GatewayModelExchange
        do {
            try Task.checkCancellation()
            exchange = try await executeModelRequest(
                request,
                body: turnRequest.body,
                traffic: upstreamTraffic,
                wire: .anthropic,
                eventID: turnRequest.eventID,
                attempt: turnRequest.attempt
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch is ProviderToolContract.Error {
            throw GatewayWebSearchError.invalidProviderResponse
        } catch {
            throw GatewayWebSearchError.providerFailed
        }
        let response = exchange.response
        defer { exchange.trace.finish() }

        let responseBody: Data
        do {
            try Task.checkCancellation()
            responseBody = try await exchange.trace.collect(response.body, upTo: maximumErrorBytes)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch is NIOTooManyBytesError {
            throw GatewayWebSearchError.responseTooLarge
        } catch {
            throw GatewayWebSearchError.providerFailed
        }
        return BufferedModelTurn(response: response, body: responseBody)
    }

    private func projectedWebSearchResponse(
        prepared: PreparedWebSearchRequest,
        traces: [WebSearchTrace],
        finalTurn: AnthropicModelTurn,
        usage: AnthropicUsage
    ) -> Response {
        let body: Data
        do {
            body = try dependencies.projector.anthropicResponse(
                prepared: prepared,
                traces: traces,
                finalTurn: finalTurn,
                usage: usage
            )
        } catch {
            return anthropicError(status: .badGateway, message: "Could not project provider response")
        }

        let headers: HTTPFields = [.contentType: "application/json"]
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: body))
        )
    }
}
