import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchCommon
import LittleSwitchSearch
import NIOCore
import NIOHTTP1

package enum GatewayAnthropicLiveError: Swift.Error {
    case providerNotReady
    case providerFailed
    case invalidProviderResponse
    case requestTooLarge
    case clientWriteFailed
}

package struct GatewayAnthropicLiveLoopState: Sendable {
    var upstreamBody: Data
    var modelAttempt = 0
    var successfulSearches = 0
    var forceFinalTurn = false
    var usage = AnthropicUsage(inputTokens: 0, outputTokens: 0)
    private var serverToolIDs: AnthropicServerToolIDSequence

    package init(upstreamBody: Data, eventID: UUID) {
        self.upstreamBody = upstreamBody
        serverToolIDs = AnthropicServerToolIDSequence(eventID: eventID)
    }

    mutating func nextServerToolID() -> String {
        serverToolIDs.next()
    }
}

extension GatewayResponder {
    package func liveWebSearchResponse(
        context: GatewayWebSearchContext,
        searchCredential: String?
    ) async throws -> Response {
        let firstResponse: GatewayModelExchange
        do {
            firstResponse = try await executeAnthropicLiveModelHead(
                body: context.prepared.upstreamBody,
                attempt: 0,
                context: context
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch GatewayAnthropicLiveError.providerNotReady {
            return anthropicError(status: .serviceUnavailable, message: "Provider is not ready")
        } catch {
            return anthropicError(status: .badGateway, message: "Provider request failed")
        }

        guard (200..<300).contains(firstResponse.response.status.code) else {
            return streamingResponse(
                firstResponse.response, eventID: context.eventID, attempt: 0, trace: firstResponse.trace)
        }

        let responder = self
        return responder.liveSearchResponse(
            makeSession: AnthropicPublicStreamSession(
                originalModel: context.prepared.originalModel,
                privateToolName: context.prepared.privateToolName
            ),
            run: { session, writer in
                try await responder.runAnthropicLiveWebSearch(
                    firstResponse: firstResponse,
                    context: context,
                    searchCredential: searchCredential,
                    session: &session,
                    writer: &writer
                )
            },
            writeFrames: { writer, frames in
                try await responder.writeAnthropicLiveFrames(frames, to: &writer)
            },
            recover: { session, error in
                switch error {
                case is CancellationError:
                    return .rethrow
                case GatewayAnthropicLiveError.clientWriteFailed:
                    return .rethrow
                default:
                    return .fail(
                        .init(
                            frames: try session.fail(message: "Internal server error"),
                            reason: String(describing: error)
                        )
                    )
                }
            }
        )
    }

    package func executeAnthropicLiveModelHead(
        body: Data,
        attempt: Int,
        context: GatewayWebSearchContext
    ) async throws -> GatewayModelExchange {
        guard body.count <= maximumRequestBytes else {
            throw GatewayAnthropicLiveError.requestTooLarge
        }
        let request: HTTPClientRequest
        do {
            request = try ProviderRequestBuilder.message(
                provider: context.target.provider,
                secret: context.providerCredential,
                headers: context.incomingHeaders,
                body: body
            )
        } catch {
            throw GatewayAnthropicLiveError.providerNotReady
        }
        let upstreamTraffic = trafficUpstreamRequest(
            attempt: attempt,
            target: context.target,
            request: request,
            body: body,
            streaming: true
        )

        let response: GatewayModelExchange
        do {
            try Task.checkCancellation()
            response = try await executeModelRequest(
                request,
                body: body,
                traffic: upstreamTraffic,
                wire: .anthropic,
                eventID: context.eventID,
                attempt: attempt
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GatewayAnthropicLiveError.providerFailed
        }
        return response
    }
}

extension GatewayResponder {
    private func runAnthropicLiveWebSearch(
        firstResponse: GatewayModelExchange,
        context: GatewayWebSearchContext,
        searchCredential: String?,
        session: inout AnthropicPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws {
        var configuration = context.configuration
        configuration.maximumUses = context.prepared.maximumUses
        var state = GatewayAnthropicLiveLoopState(
            upstreamBody: context.prepared.upstreamBody,
            eventID: context.eventID
        )
        let initialUsageRequest = AnthropicInitialUsageRequestContext(
            provider: context.target.provider,
            secret: context.providerCredential,
            incomingHeaders: context.incomingHeaders,
            upstreamBody: context.prepared.upstreamBody
        )
        var response = firstResponse

        while true {
            try Task.checkCancellation()
            guard (200..<300).contains(response.response.status.code) else {
                _ = try? await response.trace.collect(response.response.body, upTo: maximumErrorBytes)
                throw GatewayAnthropicLiveError.providerFailed
            }
            let turn = try await consumeAnthropicLiveTurn(
                response.response,
                context: AnthropicLiveTurnContext(
                    attempt: state.modelAttempt,
                    eventID: context.eventID,
                    initialUsageRequest: initialUsageRequest,
                    trace: response.trace
                ),
                session: &session,
                writer: &writer
            )
            state.usage.add(turn.usage)

            if !state.forceFinalTurn, let toolCall = turn.webSearchCall {
                try await advanceAnthropicLiveSearch(
                    state: &state,
                    search: GatewayAnthropicLiveSearchContext(
                        eventID: context.eventID,
                        turn: turn,
                        toolCall: toolCall,
                        configuration: configuration,
                        credential: searchCredential,
                        options: context.prepared.searchOptions
                    ),
                    session: &session,
                    writer: &writer
                )
                state.modelAttempt += 1
                response = try await executeAnthropicLiveModelHead(
                    body: state.upstreamBody,
                    attempt: state.modelAttempt,
                    context: context
                )
            } else {
                let frames = try session.finish(turn: turn, usage: state.usage)
                try await writeAnthropicLiveFrames(frames, to: &writer)
                break
            }
        }
    }

    private func advanceAnthropicLiveSearch(
        state: inout GatewayAnthropicLiveLoopState,
        search: GatewayAnthropicLiveSearchContext,
        session: inout AnthropicPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws {
        let serverToolID = state.nextServerToolID()
        let beginFrames = try session.beginSearch(
            toolUseID: serverToolID,
            query: search.toolCall.query
        )
        try await writeAnthropicLiveFrames(beginFrames, to: &writer)

        let outcome = try await anthropicLiveSearchOutcome(
            search: search,
            successfulSearches: state.successfulSearches
        )
        let trace = WebSearchTrace(
            toolUseID: serverToolID,
            query: search.toolCall.query,
            content: outcome.content,
            publicContentJSON: search.turn.contentJSON
        )
        try await writeAnthropicLiveFrames(
            session.finishSearch(trace),
            to: &writer
        )

        state.successfulSearches += outcome.successfulSearchIncrement
        state.forceFinalTurn = outcome.forceFinalTurn
        state.upstreamBody = try AnthropicWebSearch.followUpRequest(
            baseBody: state.upstreamBody,
            turn: search.turn,
            toolCall: search.toolCall,
            resultText: outcome.resultText,
            mode: outcome.forceFinalTurn ? .terminalError : .result,
            privateToolName: session.privateToolName
        )
    }

    private func anthropicLiveSearchOutcome(
        search: GatewayAnthropicLiveSearchContext,
        successfulSearches: Int
    ) async throws -> GatewayAnthropicLiveSearchOutcome {
        let toolCall = search.toolCall
        let configuration = search.configuration
        let outcome = try await admittedWebSearch(
            WebSearchAttemptRequest(
                rawQuery: toolCall.query,
                options: search.options,
                successfulSearches: successfulSearches,
                maximumUses: configuration.maximumUses
            ),
            configuration: configuration,
            credential: search.credential,
            eventID: search.eventID
        )
        switch outcome {
        case .invalidRequest:
            return .error(code: "invalid_request")
        case .overBudget:
            return .error(code: "max_uses_exceeded")
        case .unavailable:
            return .error(code: "unavailable")
        case .results(let results):
            return GatewayAnthropicLiveSearchOutcome(
                content: .results(results),
                resultText: AnthropicWebSearch.formatResults(results),
                successfulSearchIncrement: 1,
                forceFinalTurn: false
            )
        }
    }
}

package struct GatewayAnthropicLiveSearchContext: Sendable {
    let eventID: UUID
    let turn: AnthropicModelTurn
    let toolCall: WebSearchToolCall
    let configuration: WebSearchConfiguration
    let credential: String?
    let options: WebSearchFilterOptions
}

package struct GatewayAnthropicLiveSearchOutcome: Sendable {
    let content: WebSearchTraceContent
    let resultText: String
    let successfulSearchIncrement: Int
    let forceFinalTurn: Bool

    static func error(code: String) -> Self {
        Self(
            content: .error(code),
            resultText: code,
            successfulSearchIncrement: 0,
            forceFinalTurn: true
        )
    }
}
