import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore

/// One instance per model turn; no mutable output state is shared across lanes.
package actor ResponsesWebSocketResponseProjection {
    private typealias ResponseKey = OpenAIResponsesResponse.Key
    private typealias EventKey = OpenAIResponsesCreatedEvent.Key
    private typealias ItemEventKey = OpenAIResponsesOutputItemDoneEvent.Key
    private typealias EventField = ResponsesWebSocketContract.EventField

    private let status: Int
    private let streaming: Bool
    private let maximumBytes: Int
    private let emit: @Sendable (Data) async throws -> Void
    private let checkpoint: (@Sendable (ResponsesWebSocketEventResult) async throws -> Void)?
    private let streamID: String?
    private var decoder: ServerSentEventDecoder
    private var events: ResponsesWebSocketEvents
    private var buffered = Data()
    private var finished = false
    private var lastTerminal: ResponsesWebSocketEventResult?

    package init(
        status: Int,
        streaming: Bool,
        streamID: String?,
        maximumBytes: Int,
        emit: @escaping @Sendable (Data) async throws -> Void,
        checkpoint: (@Sendable (ResponsesWebSocketEventResult) async throws -> Void)? = nil
    ) {
        self.status = status
        self.streaming = streaming && (200..<300).contains(status)
        self.maximumBytes = maximumBytes
        self.emit = emit
        self.checkpoint = checkpoint
        self.streamID = streamID
        decoder = ServerSentEventDecoder(maximumFrameBytes: maximumBytes)
        events = ResponsesWebSocketEvents(streamID: streamID, maximumBytes: maximumBytes)
    }

    package func append(_ buffer: ByteBuffer) async throws {
        guard !finished else { throw ResponsesWebSocketEvents.Error.eventAfterTerminal }
        if streaming {
            var remaining = buffer
            while let slice = remaining.readSlice(length: min(16_384, remaining.readableBytes)) {
                if slice.readableBytes == 0 { break }
                try Task.checkCancellation()
                try await forward(decoder.append(slice))
            }
        } else {
            guard buffer.readableBytes <= maximumBytes - buffered.count else {
                throw ResponsesWebSocketEvents.Error.tooLarge
            }
            buffered.append(contentsOf: buffer.readableBytesView)
        }
    }

    package func finish() async throws {
        guard !finished else { throw ResponsesWebSocketEvents.Error.eventAfterTerminal }
        finished = true
        if streaming {
            try await forward(decoder.finish())
        } else if !(200..<300).contains(status) {
            let object = (try? JSONValue.parse(buffered).object) ?? [:]
            _ = try events.accept(ResponsesWebSocketEvents.errorEnvelope(object, status: status).wireData())
        } else {
            try await bufferedResponse()
        }
        buffered.removeAll()
    }

    package func result() throws -> ResponsesWebSocketEventResult {
        guard finished else { throw ResponsesWebSocketEvents.Error.missingTerminal }
        if var result = lastTerminal, checkpoint != nil {
            result.published = true
            return result
        }
        return try events.finish()
    }

    private func forward(_ frames: [ServerSentEventFrame]) async throws {
        for frame in frames where !frame.terminal {
            let startsResponse =
                try JSONValue.parse(frame.data).object?[OpenAIResponsesCreatedEvent.Key.type.rawValue]?.string
                == OpenAIResponsesCreatedEventType.responseCreated.rawValue
            if checkpoint != nil, lastTerminal != nil, startsResponse {
                events = ResponsesWebSocketEvents(streamID: streamID, maximumBytes: maximumBytes)
                lastTerminal = nil
            }
            if let message = try events.accept(frame.data) {
                try await emit(message)
            } else if let checkpoint {
                let terminal = try events.finish()
                lastTerminal = terminal
                try await checkpoint(terminal)
            }
        }
    }

    /// Some compatible providers return a complete JSON response despite stream=true.
    /// Publish item lifecycle events so tool consumers receive the same public items.
    private func bufferedResponse() async throws {
        guard let response = try JSONValue.parse(buffered).object,
            let identifier = response[ResponseKey.id.rawValue]?.string, !identifier.isEmpty,
            let output = response[ResponseKey.output.rawValue]?.array
        else { throw ResponsesWebSocketEvents.Error.invalidEvent }
        var initial = response
        initial[ResponseKey.status.rawValue] = .string(OpenAIResponsesStatus.inProgress.rawValue)
        initial[ResponseKey.output.rawValue] = .array([])
        try await publish([
            EventKey.type.rawValue: .string(OpenAIResponsesCreatedEventType.responseCreated.rawValue),
            EventField.sequenceNumber.rawValue: .integer(0), EventKey.response.rawValue: .object(initial),
        ])
        var sequence = 1
        for (index, item) in output.enumerated() {
            for type in [
                OpenAIResponsesOutputItemAddedEventType.responseOutputItemAdded.rawValue,
                OpenAIResponsesOutputItemDoneEventType.responseOutputItemDone.rawValue,
            ] {
                try await publish([
                    ItemEventKey.type.rawValue: .string(type), EventField.sequenceNumber.rawValue: .integer(sequence),
                    ItemEventKey.outputIndex.rawValue: .integer(index), ItemEventKey.item.rawValue: item,
                ])
                sequence += 1
            }
        }
        let status = OpenAIResponsesStatus(
            rawValue: response[ResponseKey.status.rawValue]?.string ?? OpenAIResponsesStatus.completed.rawValue)
        let terminalType: String
        switch status {
        case .completed:
            terminalType = OpenAIResponsesCompletedEventType.responseCompleted.rawValue
        case .incomplete:
            terminalType = OpenAIResponsesIncompleteEventType.responseIncomplete.rawValue
        case .failed:
            terminalType = OpenAIResponsesFailedEventType.responseFailed.rawValue
        case .inProgress, .cancelled, .queued, .none:
            throw ResponsesWebSocketEvents.Error.invalidEvent
        }
        try await publish([
            EventKey.type.rawValue: .string(terminalType), EventField.sequenceNumber.rawValue: .integer(sequence),
            EventKey.response.rawValue: .object(response),
        ])
    }

    private func publish(_ event: JSONObject) async throws {
        if let message = try events.accept(event.wireData()) { try await emit(message) }
    }
}

extension JSONObject {
    fileprivate func wireData() throws -> Data { try JSONValue.object(self).serializedData() }
}

package struct ResponsesWebSocketResponseWriter: ResponseBodyWriter {
    package let projection: ResponsesWebSocketResponseProjection

    package mutating func write(_ buffer: ByteBuffer) async throws {
        try await projection.append(buffer)
    }

    package consuming func finish(_ trailingHeaders: HTTPFields?) async throws {
        _ = trailingHeaders
        try await projection.finish()
    }
}
