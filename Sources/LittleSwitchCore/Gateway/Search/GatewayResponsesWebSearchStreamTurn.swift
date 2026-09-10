import AsyncHTTPClient
import Foundation
import Hummingbird
import LittleSwitchTransport
import NIOCore

extension GatewayResponder {
    package func consumeResponsesLiveTurn(
        _ head: GatewayResponsesLiveModelHead,
        session: inout ResponsesPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws -> ResponsesModelTurn {
        let trace = head.trace
        defer { trace.finish() }
        if head.response.headers["content-type"].contains(where: {
            $0.lowercased().contains("text/event-stream")
        }) {
            if let adapted = head.adapted {
                return try await consumeResponsesLiveChatStream(
                    head.response,
                    prepared: adapted,
                    trace: trace,
                    session: &session,
                    writer: &writer
                )
            }
            return try await consumeResponsesLiveNativeStream(
                head.response,
                trace: trace,
                session: &session,
                writer: &writer
            )
        }
        return try await consumeResponsesLiveJSON(
            head,
            trace: trace,
            session: &session,
            writer: &writer
        )
    }

    package func writeResponsesLiveFrames(
        _ frames: [Data],
        to writer: inout any ResponseBodyWriter
    ) async throws {
        try await writeLiveFrames(frames, to: &writer) { _ in
            GatewayResponsesLiveError.clientWriteFailed
        }
    }
}

extension GatewayResponder {
    private func consumeResponsesLiveNativeStream(
        _ response: HTTPClientResponse,
        trace: GatewayUpstreamResponseTrace,
        session: inout ResponsesPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws -> ResponsesModelTurn {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: maximumErrorBytes)
        var accumulator = OpenAIResponsesTurnAccumulator(
            maximumTurnBytes: maximumErrorBytes,
            toolBindings: session.nativeToolBindings,
            declaredToolBindings: session.nativeDeclaredToolBindings,
            privateToolName: session.configuration.privateSearchToolName
        )
        do {
            for try await buffer in response.body {
                trace.append(Data(buffer.readableBytesView))
                try Task.checkCancellation()
                try await publishResponsesFrames(
                    try decoder.append(buffer),
                    accumulator: &accumulator,
                    session: &session,
                    writer: &writer
                )
            }
            try await publishResponsesFrames(
                try decoder.finish(),
                accumulator: &accumulator,
                session: &session,
                writer: &writer
            )
            let turn = try accumulator.finish()
            return try OpenAIResponsesWebSearch.parseModelTurn(
                turn.rootJSON, privateToolName: session.configuration.privateSearchToolName
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch GatewayResponsesLiveError.clientWriteFailed {
            throw GatewayResponsesLiveError.clientWriteFailed
        } catch GatewayResponsesLiveError.providerTerminalFailed {
            throw GatewayResponsesLiveError.providerTerminalFailed
        } catch {
            throw GatewayResponsesLiveError.invalidProviderStream(String(describing: error))
        }
    }

    private func consumeResponsesLiveChatStream(
        _ response: HTTPClientResponse,
        prepared: PreparedResponsesChatCompletionsRequest,
        trace: GatewayUpstreamResponseTrace,
        session: inout ResponsesPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws -> ResponsesModelTurn {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: maximumErrorBytes)
        var accumulator = OpenAIChatCompletionsAccumulator(
            prepared: prepared,
            maximumTurnBytes: maximumErrorBytes
        )
        do {
            for try await buffer in response.body {
                trace.append(Data(buffer.readableBytesView))
                try Task.checkCancellation()
                try await publishResponsesChatFrames(
                    try decoder.append(buffer),
                    accumulator: &accumulator,
                    session: &session,
                    writer: &writer
                )
            }
            try await publishResponsesChatFrames(
                try decoder.finish(),
                accumulator: &accumulator,
                session: &session,
                writer: &writer
            )
            let turn = try accumulator.finish()
            return try OpenAIResponsesWebSearch.parseModelTurn(
                turn.rootJSON, privateToolName: session.configuration.privateSearchToolName
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch GatewayResponsesLiveError.clientWriteFailed {
            throw GatewayResponsesLiveError.clientWriteFailed
        } catch OpenAIResponsesChatCompletions.Error.contextLengthExceeded {
            throw OpenAIResponsesChatCompletions.Error.contextLengthExceeded
        } catch {
            throw GatewayResponsesLiveError.invalidProviderStream(String(describing: error))
        }
    }

    private func publishResponsesFrames(
        _ frames: [ServerSentEventFrame],
        accumulator: inout OpenAIResponsesTurnAccumulator,
        session: inout ResponsesPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws {
        for frame in frames {
            for event in try accumulator.consume(frame) {
                try await publishResponsesLiveEvent(
                    event,
                    session: &session,
                    writer: &writer
                )
            }
        }
    }

    private func publishResponsesChatFrames(
        _ frames: [ServerSentEventFrame],
        accumulator: inout OpenAIChatCompletionsAccumulator,
        session: inout ResponsesPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws {
        for frame in frames {
            for event in try accumulator.consume(frame) {
                try await publishResponsesLiveEvent(
                    event,
                    session: &session,
                    writer: &writer
                )
            }
        }
    }

    private func consumeResponsesLiveJSON(
        _ head: GatewayResponsesLiveModelHead,
        trace: GatewayUpstreamResponseTrace,
        session: inout ResponsesPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws -> ResponsesModelTurn {
        let data: Data
        do {
            try Task.checkCancellation()
            data = try await trace.collect(head.response.body, upTo: maximumErrorBytes)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GatewayResponsesLiveError.invalidProviderResponse
        }

        var failureCode: String?
        do {
            let responseData: Data
            if let adapted = head.adapted {
                responseData = try OpenAIResponsesChatCompletions.project(
                    responseBody: data,
                    prepared: adapted
                )
            } else {
                responseData = try normalizedResponsesLiveJSON(data)
            }
            let responseObject = try publicResponseObject(responseData)
            if responseObject["status"] as? String == ResponsesStreamTerminal.failed.rawValue {
                failureCode = (responseObject["error"] as? [String: Any])?["code"] as? String
            }
            let encoded = try OpenAIResponsesStreaming.encode(
                providerFallback: responseObject
            )
            var decoder = ServerSentEventDecoder(maximumFrameBytes: maximumErrorBytes)
            // Chat projection already restored its output names. Only a
            // native JSON response still needs the accumulator's bindings.
            var accumulator = OpenAIResponsesTurnAccumulator(
                maximumTurnBytes: maximumErrorBytes,
                toolBindings: head.adapted == nil ? session.nativeToolBindings : [:],
                declaredToolBindings: head.adapted == nil ? session.nativeDeclaredToolBindings : [:],
                privateToolName: session.configuration.privateSearchToolName
            )
            try await publishResponsesFrames(
                try decoder.append(ByteBuffer(bytes: encoded)),
                accumulator: &accumulator,
                session: &session,
                writer: &writer
            )
            try await publishResponsesFrames(
                try decoder.finish(),
                accumulator: &accumulator,
                session: &session,
                writer: &writer
            )
            return try accumulator.finish()
        } catch is CancellationError {
            throw CancellationError()
        } catch GatewayResponsesLiveError.clientWriteFailed {
            throw GatewayResponsesLiveError.clientWriteFailed
        } catch GatewayResponsesLiveError.providerTerminalFailed {
            throw GatewayResponsesLiveError.providerTerminalFailed
        } catch {
            if failureCode == "context_length_exceeded" {
                throw OpenAIResponsesChatCompletions.Error.contextLengthExceeded
            }
            throw GatewayResponsesLiveError.invalidProviderStream(String(describing: error))
        }
    }

    package func publishResponsesLiveEvent(
        _ event: ResponsesProviderStreamEvent,
        session: inout ResponsesPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws {
        let frames: [Data]
        if session.started {
            frames = try session.consumePublic(event)
        } else {
            guard case .responseStarted(let responseJSON) = event else {
                throw GatewayResponsesLiveError.invalidProviderStream(
                    "unexpected first event: \(String(describing: event).prefix(200))"
                )
            }
            frames = try session.start(responseJSON: responseJSON)
        }
        try await writeResponsesLiveFrames(frames, to: &writer)
        if case .terminal(.failed, _) = event {
            throw GatewayResponsesLiveError.providerTerminalFailed
        }
    }

}

private func normalizedResponsesLiveJSON(_ data: Data) throws -> Data {
    var response = try publicResponseObject(data)
    guard nonemptyResponsesString(response["id"]) != nil else {
        throw OpenAIResponsesWebSearch.Error.invalidResponse
    }
    response["object"] = response["object"] ?? "response"
    response["created_at"] = nonnegativeResponsesIndex(response["created_at"]) ?? 0
    response["status"] = response["status"] ?? ResponsesStreamTerminal.completed.rawValue
    response["completed_at"] = response["completed_at"] ?? response["created_at"]
    response["model"] = response["model"] ?? "provider-model"
    if response["status"] as? String == ResponsesStreamTerminal.failed.rawValue {
        guard validResponsesFailedResponse(response) else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        response["output"] = response["output"] ?? []
    } else {
        guard response["output"] is [Any],
            response["usage"] is [String: Any]
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
    }
    return try responsesStreamData(response)
}
