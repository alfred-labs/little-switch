import AsyncHTTPClient
import Foundation
import Hummingbird
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore

package struct AnthropicLiveTurnContext: Sendable {
    let attempt: Int
    let eventID: UUID
    let initialUsageRequest: AnthropicInitialUsageRequestContext?
    let trace: GatewayUpstreamResponseTrace?

    package init(
        attempt: Int,
        eventID: UUID,
        initialUsageRequest: AnthropicInitialUsageRequestContext? = nil,
        trace: GatewayUpstreamResponseTrace? = nil
    ) {
        self.attempt = attempt
        self.eventID = eventID
        self.initialUsageRequest = initialUsageRequest
        self.trace = trace
    }
}

extension GatewayResponder {
    package func consumeAnthropicLiveTurn(
        _ response: HTTPClientResponse,
        context: AnthropicLiveTurnContext,
        session: inout AnthropicPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws -> AnthropicModelTurn {
        let trace = context.trace ?? upstreamResponseTrace(eventID: context.eventID, attempt: context.attempt)
        defer { trace.finish() }
        if response.headers["content-type"].contains(where: {
            $0.lowercased().contains("text/event-stream")
        }) {
            return try await consumeAnthropicLiveEventStream(
                response,
                context: context,
                trace: trace,
                session: &session,
                writer: &writer
            )
        }
        return try await consumeAnthropicLiveJSON(
            response,
            context: context,
            trace: trace,
            session: &session,
            writer: &writer
        )
    }

    package func writeAnthropicLiveFrames(
        _ frames: [Data],
        to writer: inout any ResponseBodyWriter
    ) async throws {
        try await writeLiveFrames(frames, to: &writer) { _ in
            GatewayAnthropicLiveError.clientWriteFailed
        }
    }
}

extension GatewayResponder {
    private func consumeAnthropicLiveEventStream(
        _ response: HTTPClientResponse,
        context: AnthropicLiveTurnContext,
        trace: GatewayUpstreamResponseTrace,
        session: inout AnthropicPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws -> AnthropicModelTurn {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: maximumErrorBytes)
        var accumulator = AnthropicStreamingTurnAccumulator(
            maximumTurnBytes: maximumErrorBytes,
            privateToolName: session.privateToolName
        )

        do {
            for try await buffer in response.body {
                trace.append(Data(buffer.readableBytesView))
                try Task.checkCancellation()
                try await publishAnthropicFrames(
                    try decoder.append(buffer),
                    accumulator: &accumulator,
                    session: &session,
                    writer: &writer,
                    context: context
                )
            }
            try await publishAnthropicFrames(
                try decoder.finish(),
                accumulator: &accumulator,
                session: &session,
                writer: &writer,
                context: context
            )
            return try accumulator.finish()
        } catch is CancellationError {
            throw CancellationError()
        } catch GatewayAnthropicLiveError.clientWriteFailed {
            throw GatewayAnthropicLiveError.clientWriteFailed
        } catch {
            throw GatewayAnthropicLiveError.invalidProviderResponse
        }
    }

    private func publishAnthropicFrames(
        _ frames: [ServerSentEventFrame],
        accumulator: inout AnthropicStreamingTurnAccumulator,
        session: inout AnthropicPublicStreamSession,
        writer: inout any ResponseBodyWriter,
        context: AnthropicLiveTurnContext
    ) async throws {
        for frame in frames {
            if let event = try accumulator.consume(frame) {
                try await publishAnthropicLiveEvent(
                    event,
                    session: &session,
                    writer: &writer,
                    eventID: context.eventID,
                    initialUsageRequest: context.initialUsageRequest
                )
            }
        }
    }

    private func consumeAnthropicLiveJSON(
        _ response: HTTPClientResponse,
        context: AnthropicLiveTurnContext,
        trace: GatewayUpstreamResponseTrace,
        session: inout AnthropicPublicStreamSession,
        writer: inout any ResponseBodyWriter
    ) async throws -> AnthropicModelTurn {
        let data: Data
        do {
            try Task.checkCancellation()
            data = try await trace.collect(response.body, upTo: maximumErrorBytes)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GatewayAnthropicLiveError.invalidProviderResponse
        }

        do {
            let turn = try AnthropicWebSearch.parseModelTurn(data, privateToolName: session.privateToolName)
            for event in try anthropicLiveEvents(for: turn) {
                try await publishAnthropicLiveEvent(
                    event,
                    session: &session,
                    writer: &writer,
                    eventID: context.eventID,
                    initialUsageRequest: context.initialUsageRequest
                )
            }
            return turn
        } catch is CancellationError {
            throw CancellationError()
        } catch GatewayAnthropicLiveError.clientWriteFailed {
            throw GatewayAnthropicLiveError.clientWriteFailed
        } catch {
            throw GatewayAnthropicLiveError.invalidProviderResponse
        }
    }

    package func publishAnthropicLiveEvent(
        _ event: AnthropicProviderStreamEvent,
        session: inout AnthropicPublicStreamSession,
        writer: inout any ResponseBodyWriter,
        eventID: UUID? = nil,
        initialUsageRequest: AnthropicInitialUsageRequestContext? = nil
    ) async throws {
        let frames: [Data]
        if session.started {
            frames = try session.consumePublic(event)
        } else {
            switch event {
            case .messageStart(let messageJSON):
                frames = try session.start(
                    from: await resolvedAnthropicInitialUsageMessageStart(
                        messageJSON,
                        request: initialUsageRequest,
                        eventID: eventID
                    )
                )
            case .ping:
                return
            default:
                throw GatewayAnthropicLiveError.invalidProviderResponse
            }
        }
        try await writeAnthropicLiveFrames(frames, to: &writer)
    }

    private func resolvedAnthropicInitialUsageMessageStart(
        _ messageJSON: Data,
        request: AnthropicInitialUsageRequestContext?,
        eventID: UUID?
    ) async throws -> AnthropicProviderStreamEvent {
        var message: AnthropicMessage
        var usage: AnthropicUsageFields
        do {
            message = try WireCodec.decode(AnthropicMessage.self, from: messageJSON).value
            usage = try AnthropicUsageFields(wireJSON: message.usage ?? .null)
        } catch {
            throw GatewayAnthropicLiveError.invalidProviderResponse
        }
        let inputTokens = try usage.inputTokens.value.map(anthropicTokenCount) ?? 0
        guard inputTokens == 0, let request else {
            return .messageStart(messageJSON: messageJSON)
        }

        let resolution = try await dependencies.initialUsageResolver.estimate(
            request: request,
            transport: transport
        )
        try Task.checkCancellation()
        let resolvedTokens: Int
        switch resolution {
        case .native(let tokens), .providerEstimate(let tokens, _),
            .localEstimate(let tokens, _, _):
            resolvedTokens = tokens
        }
        guard resolvedTokens >= 0 else {
            throw GatewayAnthropicLiveError.invalidProviderResponse
        }

        usage.inputTokens = .value(JSONNumber(resolvedTokens))
        message.usage = try usage.wireJSON()
        if let eventID, let estimate = anthropicTrafficEstimate(for: resolution) {
            await GatewayMonitoringScope.current?.estimatedInput(estimate.tokenCount)
            trafficRecorder.record(
                eventID: eventID,
                action: .initialUsageEstimate(estimate)
            )
        }
        return .messageStart(messageJSON: try WireCodec.encode(message))
    }

}

package func anthropicLiveEvents(
    for turn: AnthropicModelTurn
) throws -> [AnthropicProviderStreamEvent] {
    let message = AnthropicMessage(
        content: [],
        id: turn.id,
        stopReason: .null,
        stopSequence: .null,
        usage: try AnthropicUsageFields(
            inputTokens: .value(JSONNumber(turn.usage.inputTokens)), outputTokens: .value(JSONNumber(0))
        ).wireJSON(),
        additionalFields: [
            AnthropicMessageMetadata.Key.type.rawValue: .string(AnthropicMessageMetadataType.message.rawValue),
            AnthropicMessageMetadata.Key.role.rawValue: .string(AnthropicMessageMetadataRole.assistant.rawValue),
        ]
    )
    var events: [AnthropicProviderStreamEvent] = [
        .messageStart(messageJSON: try WireCodec.encode(message))
    ]

    guard let blocks = try WireCodec.decode(JSONValue.self, from: turn.contentJSON).value.array else {
        throw GatewayAnthropicLiveError.invalidProviderResponse
    }
    for (index, block) in blocks.enumerated() {
        events += try anthropicLiveBlockEvents(block, index: index)
    }

    let stopReason = turn.stopReason.map(JSONValue.string) ?? .null
    events.append(
        .messageDelta(
            deltaJSON: try anthropicLiveData([
                AnthropicMessageDelta.Key.stopReason.rawValue: stopReason,
                AnthropicMessageDelta.Key.stopSequence.rawValue: try AnthropicWebSearch.fragmentObject(
                    from: turn.stopSequenceJSON
                ),
            ]),
            usageJSON: try WireCodec.encode(
                AnthropicUsageFields(
                    inputTokens: .value(JSONNumber(turn.usage.inputTokens)),
                    outputTokens: .value(JSONNumber(turn.usage.outputTokens))
                ))
        )
    )
    events.append(.messageStop)
    return events
}

private func anthropicLiveBlockEvents(
    _ block: JSONValue,
    index: Int
) throws -> [AnthropicProviderStreamEvent] {
    var startBlock = try AnthropicContentBlock(wireJSON: block)
    var events: [AnthropicProviderStreamEvent] = []
    var inputDelta: AnthropicProviderStreamEvent?
    let input: JSONValue?
    switch startBlock {
    case .toolUse(var tool):
        input = tool.input
        tool.input = [:]
        startBlock = .toolUse(tool)
    case .serverToolUse(var tool):
        input = tool.input
        tool.input = [:]
        startBlock = .serverToolUse(tool)
    default:
        input = nil
    }
    if let input {
        guard input.object != nil else {
            throw GatewayAnthropicLiveError.invalidProviderResponse
        }
        // The exact JSON codec emits UTF-8.
        // swiftlint:disable:next optional_data_string_conversion
        let partialJSON = String(decoding: try input.serializedData(), as: UTF8.self)
        inputDelta = .contentDelta(
            index: index,
            deltaJSON: try WireCodec.encode(AnthropicInputJSONDelta(partialJson: partialJSON, type: .inputJsonDelta))
        )
    }

    events.append(
        .contentStart(index: index, blockJSON: try WireCodec.encode(startBlock))
    )
    if let inputDelta {
        events.append(inputDelta)
    }
    events.append(.contentStop(index: index))
    return events
}

private func anthropicLiveData(_ value: [String: JSONValue]) throws -> Data {
    try anthropicJSON(value).serializedData()
}
