import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

extension GatewayResponder {
    package func chatCompletionsResponsesResponse(
        _ context: TransparentResponsesContext,
        attempt: Int = 0
    ) async throws -> Response {
        let prepared: PreparedResponsesChatCompletionsRequest
        do {
            let mode: ResponsesChatCompletionsMode =
                context.streaming ? .streaming(toolStream: true) : .buffered
            prepared = try OpenAIResponsesChatCompletions.prepare(
                body: context.body,
                targetModel: context.target.model.id,
                providerID: context.target.provider.id,
                mode: mode
            )
        } catch {
            return openAIError(status: .badRequest, message: "Invalid Responses request")
        }
        guard prepared.upstreamBody.count <= maximumRequestBytes else {
            return openAIError(status: .contentTooLarge, message: "Request body is too large")
        }
        let request: HTTPClientRequest
        do {
            request = try ProviderRequestBuilder.chatCompletions(
                provider: context.target.provider,
                secret: context.credential,
                headers: context.incomingHeaders,
                body: prepared.upstreamBody
            )
        } catch {
            return openAIError(status: .serviceUnavailable, message: "Provider is not ready")
        }

        try Task.checkCancellation()

        trafficRecorder.record(
            eventID: context.eventID,
            action: .upstreamRequest(
                trafficUpstreamRequest(
                    attempt: attempt,
                    route: ResponsesTrafficRoute(
                        claudeRoute: context.model,
                        target: context.target
                    ),
                    request: request,
                    body: prepared.upstreamBody,
                    streaming: prepared.streaming
                )
            )
        )

        let exchange: GatewayModelExchange
        do {
            exchange = try await executeModelRequest(
                request,
                body: prepared.upstreamBody,
                wire: .chatCompletions,
                eventID: context.eventID,
                attempt: attempt,
                declaredToolBindings: prepared.declaredToolBindings,
                toolNameCatalog: prepared.toolNameCatalog
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return openAIError(status: .badGateway, message: "Provider request failed")
        }
        let upstream = exchange.response
        // The adapter's own route missing is the mirror lesson: only native
        // can be left, so a stale adapter verdict relearns instead of
        // relaying the 404 forever.
        await recordChatCompletionsRouteAbsent(
            providerID: context.target.provider.id,
            status: UInt(upstream.status.code)
        )

        if prepared.streaming, (200..<300).contains(upstream.status.code) {
            return liveChatCompletionsResponse(
                upstream,
                prepared: prepared,
                eventID: context.eventID,
                traffic: exchange.trace
            )
        }

        return try await bufferedChatCompletionsResponse(
            upstream,
            prepared: prepared,
            traffic: exchange.trace
        )
    }
}

private enum GatewayChatCompletionsLiveError: Swift.Error {
    case unexpectedFirstEvent(String)
    case clientWriteFailed
    case providerTerminalFailed
}

extension GatewayResponder {
    private func bufferedChatCompletionsResponse(
        _ upstream: HTTPClientResponse,
        prepared: PreparedResponsesChatCompletionsRequest,
        traffic: GatewayUpstreamResponseTrace
    ) async throws -> Response {
        let upstreamBody: Data
        do {
            upstreamBody = try await traffic.collect(upstream.body, upTo: maximumErrorBytes)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return openAIError(status: .badGateway, message: "Provider request failed")
        }

        guard (200..<300).contains(upstream.status.code) else {
            return bufferedResponse(upstream, body: upstreamBody)
        }

        let projected: Data
        do {
            projected = try OpenAIResponsesChatCompletions.project(
                responseBody: upstreamBody,
                prepared: prepared
            )
        } catch {
            return openAIError(status: .badGateway, message: "Invalid provider response")
        }

        let headers: HTTPFields = [.contentType: "application/json"]
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: projected))
        )
    }

    private func liveChatCompletionsResponse(
        _ upstream: HTTPClientResponse,
        prepared: PreparedResponsesChatCompletionsRequest,
        eventID: UUID,
        traffic: GatewayUpstreamResponseTrace
    ) -> Response {
        var headers: HTTPFields = [.contentType: "text/event-stream"]
        if let cacheControl = HTTPField.Name("cache-control") {
            headers[cacheControl] = "no-cache"
        }
        let responder = self
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(contentLength: nil) { writer in
                var session = ResponsesPublicStreamSession(
                    chatCompletions: prepared
                )
                var committedFailure = false
                var failureReason: String?
                var toolError: ProviderToolContract.Error?
                do {
                    try await responder.consumeLiveChatCompletions(
                        upstream,
                        prepared: prepared,
                        traffic: traffic,
                        session: &session,
                        writer: &writer
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch GatewayChatCompletionsLiveError.clientWriteFailed {
                    throw GatewayChatCompletionsLiveError.clientWriteFailed
                } catch GatewayChatCompletionsLiveError.providerTerminalFailed {
                    committedFailure = true
                } catch OpenAIResponsesChatCompletions.Error.contextLengthExceeded {
                    let frames = try session.fail(
                        code: "context_length_exceeded",
                        message: "Internal server error"
                    )
                    try await responder.writeLiveChatCompletionsFrames(
                        frames,
                        to: &writer
                    )
                    committedFailure = true
                } catch {
                    failureReason = String(describing: error)
                    toolError = error as? ProviderToolContract.Error
                    let frames = try session.fail(
                        message: String(describing: error),
                        wording: .init(error: error, eventID: eventID)
                    )
                    try await responder.writeLiveChatCompletionsFrames(
                        frames,
                        to: &writer
                    )
                    committedFailure = true
                }
                try await writer.finish(nil)
                if committedFailure {
                    throw GatewayCommittedStreamFailure(reason: failureReason, toolError: toolError)
                }
            }
        )
    }
}

extension GatewayResponder {
    private func consumeLiveChatCompletions(
        _ upstream: HTTPClientResponse,
        prepared: PreparedResponsesChatCompletionsRequest,
        traffic: GatewayUpstreamResponseTrace,
        session: inout ResponsesPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws {
        if upstream.headers["content-type"].contains(where: {
            $0.lowercased().contains("text/event-stream")
        }) {
            try await consumeLiveChatCompletionsSSE(
                upstream,
                prepared: prepared,
                traffic: traffic,
                session: &session,
                writer: &writer
            )
            return
        }
        try await consumeLiveChatCompletionsJSON(
            upstream,
            prepared: prepared,
            traffic: traffic,
            writer: &writer
        )
    }

    private func consumeLiveChatCompletionsSSE(
        _ upstream: HTTPClientResponse,
        prepared: PreparedResponsesChatCompletionsRequest,
        traffic: GatewayUpstreamResponseTrace,
        session: inout ResponsesPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: maximumErrorBytes)
        var accumulator = OpenAIChatCompletionsAccumulator(
            prepared: prepared,
            maximumTurnBytes: maximumErrorBytes
        )
        defer { traffic.finish() }

        for try await buffer in upstream.body {
            traffic.append(Data(buffer.readableBytesView))
            try Task.checkCancellation()
            try await publishLiveChatCompletionsFrames(
                try decoder.append(buffer),
                accumulator: &accumulator,
                session: &session,
                writer: &writer
            )
        }
        try await publishLiveChatCompletionsFrames(
            try decoder.finish(),
            accumulator: &accumulator,
            session: &session,
            writer: &writer
        )
        let turn = try accumulator.finish()
        try await writeLiveChatCompletionsFrames(
            try session.finish(responseJSON: turn.rootJSON, usage: turn.usage),
            to: &writer
        )
    }

    private func publishLiveChatCompletionsFrames(
        _ frames: [ServerSentEventFrame],
        accumulator: inout OpenAIChatCompletionsAccumulator,
        session: inout ResponsesPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws {
        for frame in frames {
            for event in try accumulator.consume(frame) {
                try await publishLiveChatCompletionsEvent(
                    event,
                    session: &session,
                    writer: &writer
                )
            }
        }
    }

    private func consumeLiveChatCompletionsJSON(
        _ upstream: HTTPClientResponse,
        prepared: PreparedResponsesChatCompletionsRequest,
        traffic: GatewayUpstreamResponseTrace,
        writer: inout any ResponseBodyWriter
    ) async throws {
        let body = try await traffic.collect(upstream.body, upTo: maximumErrorBytes)
        try Task.checkCancellation()
        let projected = try OpenAIResponsesChatCompletions.project(
            responseBody: body,
            prepared: prepared
        )
        let terminalStatus = try OpenAIResponsesChatCompletions.terminalStatus(
            responseBody: body
        )
        try await writeLiveChatCompletionsFrames([projected], to: &writer)
        if terminalStatus == .failed {
            throw GatewayChatCompletionsLiveError.providerTerminalFailed
        }
    }

    package func publishLiveChatCompletionsEvent(
        _ event: ResponsesProviderStreamEvent,
        session: inout ResponsesPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws {
        let frames: [Data]
        if session.started {
            frames = try session.consumePublic(event)
        } else {
            guard case .responseStarted(let responseJSON) = event else {
                throw GatewayChatCompletionsLiveError.unexpectedFirstEvent(
                    String(describing: event).prefix(200).description
                )
            }
            frames = try session.start(responseJSON: responseJSON)
        }
        try await writeLiveChatCompletionsFrames(frames, to: &writer)
    }

    private func writeLiveChatCompletionsFrames(
        _ frames: [Data],
        to writer: inout any ResponseBodyWriter
    ) async throws {
        for frame in frames {
            do {
                try Task.checkCancellation()
                try await writer.write(ByteBuffer(bytes: frame))
                try Task.checkCancellation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw GatewayChatCompletionsLiveError.clientWriteFailed
            }
        }
    }

}
