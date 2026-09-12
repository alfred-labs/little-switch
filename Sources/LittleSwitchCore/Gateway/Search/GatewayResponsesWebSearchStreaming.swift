import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchSearch
import NIOCore
import NIOHTTP1

package enum GatewayResponsesLiveError: Swift.Error {
    case providerNotReady
    case providerFailed
    case invalidProviderResponse
    case invalidProviderRequest(String)
    case invalidProviderStream(String)
    case requestTooLarge
    case clientWriteFailed
    case providerTerminalFailed
}

package struct GatewayResponsesLiveModelHead {
    let response: HTTPClientResponse
    let adapted: PreparedResponsesChatCompletionsRequest?
    let trace: GatewayUpstreamResponseTrace
}

private struct GatewayResponsesLiveLoopState {
    var upstreamBody: Data
    var modelAttempt = 0
    var successfulSearches = 0
    var forceFinalTurn = false
    var searchCount = 0
    var usage = ResponsesUsage(inputTokens: 0, outputTokens: 0)
    let searchIDBase: String

    init(upstreamBody: Data) {
        self.upstreamBody = upstreamBody
        searchIDBase = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    mutating func nextSearchID() -> String {
        searchCount += 1
        return "ws_\(searchIDBase)_\(searchCount)"
    }
}

private struct GatewayResponsesLiveSearchOutcome {
    let resultText: String
    let successfulSearchIncrement: Int
    let forceFinalTurn: Bool
    var sources: [String] = []

    static func error(_ code: String) -> Self {
        Self(
            resultText: code,
            successfulSearchIncrement: 0,
            forceFinalTurn: true
        )
    }
}

private struct GatewayResponsesLiveSearch {
    let eventID: UUID
    let turn: ResponsesModelTurn
    let toolCall: ResponsesWebSearchToolCall
    let configuration: WebSearchConfiguration
    let credential: String?
    let options: WebSearchFilterOptions
}

extension GatewayResponder {
    package func liveResponsesWebSearchResponse(
        context: GatewayResponsesWebSearchContext,
        attemptOffset: Int = 0
    ) async throws -> Response {
        let firstHead: GatewayResponsesLiveModelHead
        do {
            firstHead = try await executeResponsesLiveModelHead(
                body: context.prepared.upstreamBody,
                attempt: attemptOffset,
                context: context
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch GatewayResponsesLiveError.providerNotReady {
            return openAIError(status: .serviceUnavailable, message: "Provider is not ready")
        } catch {
            return openAIError(status: .badGateway, message: "Provider request failed")
        }

        guard (200..<300).contains(firstHead.response.status.code) else {
            let nativeProbeFailed =
                !context.needsChatCompletionsAdapter
                && responsesAdapterFallbackApplies(
                    status: UInt(firstHead.response.status.code),
                    provider: context.target.provider
                )
            if nativeProbeFailed {
                // Consume the small error body so the pooled connection
                // survives for the adapter retry to the same host.
                _ = try? await firstHead.trace.collect(firstHead.response.body, upTo: 16 * 1_024)
                // The native first head proved the provider has no
                // /v1/responses; the ledger just learned it, so this request
                // runs on the adapter instead of relaying the 404 to Codex.
                // The retry records under its own attempt so the traffic log
                // keeps both exchanges.
                return try await liveResponsesWebSearchResponse(
                    context: context.usingChatCompletionsAdapter(),
                    attemptOffset: 1
                )
            }
            return streamingResponse(
                firstHead.response,
                eventID: context.eventID,
                attempt: attemptOffset,
                trace: firstHead.trace
            )
        }

        let responder = self
        return responder.liveSearchResponse(
            makeSession: ResponsesPublicStreamSession(webSearch: context.prepared),
            run: { session, writer in
                try await responder.runResponsesLiveWebSearch(
                    firstHead: firstHead,
                    attemptOffset: attemptOffset,
                    context: context,
                    session: &session,
                    writer: &writer
                )
            },
            writeFrames: { writer, frames in
                try await responder.writeResponsesLiveFrames(frames, to: &writer)
            },
            recover: { session, error in
                switch error {
                case is CancellationError:
                    return .rethrow
                case GatewayResponsesLiveError.clientWriteFailed:
                    return .rethrow
                case GatewayResponsesLiveError.providerTerminalFailed:
                    return .swallow
                // A stream that ends without a terminal event is an upstream
                // disconnection mid-turn, not a server bug: name it so the
                // client sees why its stream stopped.
                case GatewayResponsesLiveError.invalidProviderStream("streamEndedBeforeTerminal"):
                    return .fail(
                        .init(
                            frames: try session.fail(
                                message: "upstream stream ended before terminal",
                                wording: .upstreamEndedBeforeCompletion
                            ),
                            reason: String(describing: error)
                        )
                    )
                case OpenAIResponsesChatCompletions.Error.contextLengthExceeded:
                    return .fail(
                        .init(
                            frames: try session.fail(
                                code: "context_length_exceeded",
                                message: "Internal server error"
                            ),
                            reason: nil
                        )
                    )
                default:
                    return .fail(
                        .init(
                            frames: try session.fail(
                                message: String(describing: error),
                                wording: .init(error: error, eventID: context.eventID)
                            ),
                            reason: String(describing: error),
                            toolError: error as? ProviderToolContract.Error
                        )
                    )
                }
            }
        )
    }

    package func executeResponsesLiveModelHead(
        body: Data,
        attempt: Int,
        context: GatewayResponsesWebSearchContext
    ) async throws -> GatewayResponsesLiveModelHead {
        guard body.count <= maximumRequestBytes else {
            throw GatewayResponsesLiveError.requestTooLarge
        }
        let prepared = try responsesLiveModelRequest(body: body, context: context)
        guard prepared.body.count <= maximumRequestBytes else {
            throw GatewayResponsesLiveError.requestTooLarge
        }
        trafficRecorder.record(
            eventID: context.eventID,
            action: .upstreamRequest(
                trafficUpstreamRequest(
                    attempt: attempt,
                    route: ResponsesTrafficRoute(
                        claudeRoute: context.prepared.originalModel,
                        target: context.target
                    ),
                    request: prepared.request,
                    body: prepared.body,
                    streaming: true
                )
            )
        )

        let exchange: GatewayModelExchange
        do {
            try Task.checkCancellation()
            exchange = try await executeModelRequest(
                prepared.request,
                body: prepared.body,
                wire: context.needsChatCompletionsAdapter ? .chatCompletions : .responses,
                eventID: context.eventID,
                attempt: attempt,
                declaredToolBindings: prepared.adapted?.declaredToolBindings
                    ?? context.prepared.declaredToolBindings,
                toolNameCatalog: prepared.adapted?.toolNameCatalog ?? context.prepared.toolNameCatalog
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GatewayResponsesLiveError.providerFailed
        }
        let response = exchange.response
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
        return GatewayResponsesLiveModelHead(
            response: response,
            adapted: prepared.adapted,
            trace: exchange.trace
        )
    }
}

extension GatewayResponder {
    package func responsesLiveModelRequest(
        body: Data,
        context: GatewayResponsesWebSearchContext
    ) throws -> GatewayResponsesLiveModelRequest {
        let needsAdapter = context.needsChatCompletionsAdapter

        let adapted: PreparedResponsesChatCompletionsRequest?
        let requestBody: Data
        do {
            if needsAdapter {
                let prepared = try OpenAIResponsesChatCompletions.prepare(
                    body: body,
                    targetModel: context.target.model.id,
                    providerID: context.target.provider.id,
                    mode: .streaming(toolStream: true),
                    inheritedToolBindings: context.prepared.toolBindings,
                    inheritedDeclaredToolBindings: context.prepared.declaredToolBindings,
                    inheritedToolNameCatalog: context.prepared.toolNameCatalog,
                    inheritedToolSearchContract: context.prepared.toolSearchContract
                )
                adapted = prepared
                requestBody = prepared.upstreamBody
            } else {
                adapted = nil
                requestBody = try ResponsesChatCompletionsReasoning.nativeRequestBody(
                    OpenAIResponsesWebSearch.streamingRequestBody(body), providerID: context.target.provider.id
                )
            }
        } catch {
            throw GatewayResponsesLiveError.invalidProviderRequest(String(describing: error))
        }

        let request: HTTPClientRequest
        do {
            request = try responsesProviderRequest(
                needsAdapter: needsAdapter,
                context: context,
                body: requestBody
            )
        } catch {
            throw GatewayResponsesLiveError.providerNotReady
        }
        return GatewayResponsesLiveModelRequest(
            request: request,
            adapted: adapted,
            body: requestBody
        )
    }

    private func runResponsesLiveWebSearch(
        firstHead: GatewayResponsesLiveModelHead,
        attemptOffset: Int,
        context: GatewayResponsesWebSearchContext,
        session: inout ResponsesPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws {
        var configuration = context.configuration
        configuration.maximumUses = context.prepared.maximumUses
        var state = GatewayResponsesLiveLoopState(
            upstreamBody: context.prepared.upstreamBody
        )
        var head = firstHead

        while true {
            try Task.checkCancellation()
            guard (200..<300).contains(head.response.status.code) else {
                _ = try? await head.trace.collect(head.response.body, upTo: maximumErrorBytes)
                throw GatewayResponsesLiveError.providerFailed
            }
            let turn = try await consumeResponsesLiveTurn(
                head,
                session: &session,
                writer: &writer
            )
            state.usage.add(turn.usage)

            if !state.forceFinalTurn, let toolCall = turn.webSearchCall {
                try await advanceResponsesLiveSearch(
                    state: &state,
                    search: GatewayResponsesLiveSearch(
                        eventID: context.eventID,
                        turn: turn,
                        toolCall: toolCall,
                        configuration: configuration,
                        credential: context.searchCredential,
                        options: context.prepared.searchOptions
                    ),
                    session: &session,
                    writer: &writer
                )
                state.modelAttempt += 1
                head = try await executeResponsesLiveModelHead(
                    body: state.upstreamBody,
                    attempt: attemptOffset + state.modelAttempt,
                    context: context
                )
            } else {
                try await writeResponsesLiveFrames(
                    session.finish(responseJSON: turn.rootJSON, usage: state.usage),
                    to: &writer
                )
                break
            }
        }
    }

    private func advanceResponsesLiveSearch(
        state: inout GatewayResponsesLiveLoopState,
        search: GatewayResponsesLiveSearch,
        session: inout ResponsesPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws {
        let searchID = state.nextSearchID()
        try await writeResponsesLiveFrames(
            session.beginSearch(id: searchID, query: search.toolCall.query),
            to: &writer
        )

        let outcome = try await responsesLiveSearchOutcome(
            search: search,
            successfulSearches: state.successfulSearches,
            eventID: search.eventID
        )
        try await writeResponsesLiveFrames(
            session.finishSearch(
                id: searchID,
                query: search.toolCall.query,
                sources: outcome.sources,
                failed: outcome.forceFinalTurn
            ),
            to: &writer
        )

        state.successfulSearches += outcome.successfulSearchIncrement
        state.forceFinalTurn = outcome.forceFinalTurn
        state.upstreamBody = try OpenAIResponsesWebSearch.followUpRequest(
            baseBody: state.upstreamBody,
            turn: search.turn,
            toolCall: search.toolCall,
            resultText: outcome.resultText,
            mode: outcome.forceFinalTurn ? .terminalError : .result
        )
    }

    private func responsesLiveSearchOutcome(
        search: GatewayResponsesLiveSearch,
        successfulSearches: Int,
        eventID: UUID
    ) async throws -> GatewayResponsesLiveSearchOutcome {
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
            eventID: eventID
        )
        switch outcome {
        case .invalidRequest:
            return .error("invalid_request")
        case .overBudget:
            return .error("max_uses_exceeded")
        case .unavailable:
            return .error("unavailable")
        case .results(let results):
            return GatewayResponsesLiveSearchOutcome(
                resultText: AnthropicWebSearch.formatResults(results),
                successfulSearchIncrement: 1,
                forceFinalTurn: false,
                sources: results.map(\.url)
            )
        }
    }
}

package struct GatewayResponsesLiveModelRequest {
    package let request: HTTPClientRequest
    package let adapted: PreparedResponsesChatCompletionsRequest?
    package let body: Data
}
