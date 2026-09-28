import Foundation
import LittleSwitchWire

/// A single connection coordinator owns this value. Queued requests resolve
/// their parent only when runnable; active turns own immutable replay copies.
package struct ResponsesWebSocketState: Sendable {
    private struct ActiveTurn: Sendable {
        let turn: ResponsesWebSocketTurn
        let input: ResponsesWebSocketInput
        let retainedBytes: Int
    }

    private let limits: ResponsesWebSocketLimits
    private var queue: [ResponsesWebSocketRequest] = []
    private var queuedBytes = 0
    private var namedStreams: Set<String> = []
    private var active: [UUID: ActiveTurn] = [:]
    private var activeBytes = 0
    private var history = ResponsesWebSocketHistoryCache()

    package init(limits: ResponsesWebSocketLimits = .init()) {
        self.limits = limits
    }

    package mutating func enqueue(_ frame: Data) throws {
        let envelope = try ResponsesWebSocketRequest.Envelope(frame, maximumBytes: limits.maxFrameBytes)
        do {
            let request = try ResponsesWebSocketRequest(envelope)
            guard queue.count < limits.maxQueuedRequests,
                request.retainedBytes <= limits.maxQueuedBytes - queuedBytes
            else {
                throw ResponsesWebSocketFailure(
                    status: 429,
                    code: "websocket_connection_limit_reached",
                    message: "WebSocket request queue is full",
                    streamID: request.streamID)
            }
            if let streamID = request.streamID {
                guard namedStreams.contains(streamID) || namedStreams.count < limits.maxNamedStreams else {
                    throw ResponsesWebSocketFailure(
                        status: 400,
                        code: "websocket_stream_limit_reached",
                        message: "WebSocket named stream limit reached",
                        streamID: streamID,
                        parameter: ResponsesWebSocketContract.RequestField.streamID.rawValue)
                }
                namedStreams.insert(streamID)
            }
            queue.append(request)
            queuedBytes += request.retainedBytes
        } catch {
            history.evictParent(envelope.previousResponseID, streamID: envelope.streamID)
            throw error
        }
    }

    package mutating func next() -> Result<ResponsesWebSocketTurn, ResponsesWebSocketFailure>? {
        guard active.count < limits.maxActiveResponses else { return nil }
        var visitedLanes = Set<String?>()
        for (index, request) in queue.enumerated() {
            guard visitedLanes.insert(request.streamID).inserted,
                !active.values.contains(where: { $0.turn.streamID == request.streamID })
            else { continue }
            let parent = request.previousResponseID.flatMap { history[$0] }
            if request.previousResponseID != nil && parent == nil {
                removeQueued(at: index)
                return .failure(
                    ResponsesWebSocketFailure(
                        status: 400,
                        code: "previous_response_not_found",
                        message: "Previous response was not found",
                        streamID: request.streamID,
                        parameter: ResponsesWebSocketContract.RequestField.previousResponseID.rawValue))
            }
            let bytes = request.activeBytes(parent: parent)
            guard bytes <= limits.maxActiveBytes else {
                removeQueued(at: index)
                history.evictParent(request.previousResponseID, streamID: request.streamID)
                return .failure(
                    ResponsesWebSocketFailure(
                        status: 413,
                        code: "request_too_large",
                        message: "Reconstructed WebSocket request is too large",
                        streamID: request.streamID,
                        parameter: OpenAIResponsesRequestEnvelope.Key.input.rawValue))
            }
            guard bytes <= limits.maxActiveBytes - activeBytes else { continue }
            removeQueued(at: index)
            let input = parent?.input.appending(request.input) ?? request.input
            let turn = request.turn(input: input)
            active[turn.id] = ActiveTurn(turn: turn, input: input, retainedBytes: bytes)
            activeBytes += bytes
            if let previous = request.previousResponseID { history.touch(previous) }
            return .success(turn)
        }
        return nil
    }

    package mutating func finish(_ turn: ResponsesWebSocketTurn, completion: ResponsesWebSocketCompletion?) throws {
        guard let active = active.removeValue(forKey: turn.id) else { return }
        let owned = active.turn
        activeBytes -= active.retainedBytes
        guard let completion else {
            history.evictParent(owned.previousResponseID, streamID: owned.streamID)
            return
        }
        do {
            guard !completion.responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                completion.output.count <= limits.maxResponseBytes,
                let output = try? WireCodec.decode([JSONValue].self, from: completion.output).value,
                output.allSatisfy({ $0.object != nil })
            else {
                throw ResponsesWebSocketFailure(
                    status: 502, code: "invalid_response", message: "Invalid response history", streamID: owned.streamID
                )
            }
            let outputInput = try ResponsesWebSocketInput(output)
            let input = owned.replacesHistory ? outputInput : active.input.appending(outputInput)
            history.store(
                responseID: completion.responseID,
                streamID: owned.streamID,
                input: input,
                maximumBytes: limits.maxHistoryBytes)
        } catch {
            history.evictParent(owned.previousResponseID, streamID: owned.streamID)
            throw error
        }
    }

    private mutating func removeQueued(at index: Int) {
        queuedBytes -= queue.remove(at: index).retainedBytes
    }
}
