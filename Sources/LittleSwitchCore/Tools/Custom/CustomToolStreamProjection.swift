import Foundation
import LittleSwitchTransport
import LittleSwitchWire

/// The envelope is not incrementally decoded: an unfinished JSON prefix is
/// never an executable custom input. Completion carries the entire input.
struct CustomToolStreamProjection {
    let projection: CustomToolProjection
    let maximumBytes: Int
    static let maximumCalls = 128
    var responses = CustomToolResponsesStreamState()
    var chat = CustomToolChatStreamState()
    enum Phase { case streaming, ended, finished }
    var phase = Phase.streaming

    mutating func consume(_ frame: ServerSentEventFrame) throws -> CustomToolFrameRewrite.Edit {
        if frame.terminal {
            guard phase != .finished else { throw CustomToolProjection.Error.invalidResponse }
            try requireComplete()
            phase = .finished
            return .keep
        }
        guard !frame.data.isEmpty else { return .keep }
        guard phase == .streaming else { throw CustomToolProjection.Error.invalidResponse }
        let value = try JSONValue.parse(frame.data)
        guard value.object != nil else { throw CustomToolProjection.Error.invalidResponse }
        let type = value.object?[OpenAIResponsesCompletedEvent.Key.type.rawValue]?.string ?? frame.event ?? ""
        if [
            OpenAIResponsesErrorEventType.error.rawValue,
            OpenAIResponsesFailedEventType.responseFailed.rawValue,
            OpenAIResponsesIncompleteEventType.responseIncomplete.rawValue,
        ].contains(type) {
            clear()
            phase = .ended
            return .keep
        }
        let result: JSONValue?
        switch projection.wire {
        case .responses:
            result = try responses.consume(value, type: type, projection: projection, maximumBytes: maximumBytes)
            if type == OpenAIResponsesCompletedEventType.responseCompleted.rawValue {
                try requireComplete()
                phase = .ended
            }
        case .chatCompletions:
            result = try chat.consume(value, projection: projection, maximumBytes: maximumBytes)
        case .anthropic: result = value
        }
        guard let result else { return .suppress }
        return result == value ? .keep : .replace(result)
    }

    func finish() throws {
        try requireComplete()
        guard phase != .streaming || (responses.calls.isEmpty && chat.calls.isEmpty) else {
            throw CustomToolProjection.Error.invalidResponse
        }
    }

    mutating func clear() {
        responses = CustomToolResponsesStreamState()
        chat = CustomToolChatStreamState()
    }

    private func requireComplete() throws {
        guard responses.calls.values.allSatisfy({ $0.input != nil && $0.itemDone }),
            chat.calls.values.allSatisfy(\.completed)
        else {
            throw CustomToolProjection.Error.invalidResponse
        }
    }
}
