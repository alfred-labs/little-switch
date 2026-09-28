import Foundation
import LittleSwitchWire

/// Bounded ordered work for the steering writer, independent of the event pump.
struct ResponsesWebSocketSteeringQueue {
    let input: AsyncStream<ResponsesWebSocketSteering>.Continuation
    let limits: ResponsesWebSocketLimits
    private var count = 0
    private var bytes = 0

    init(input: AsyncStream<ResponsesWebSocketSteering>.Continuation, limits: ResponsesWebSocketLimits) {
        self.input = input
        self.limits = limits
    }

    mutating func enqueue(_ frame: Data, supported: Bool) throws -> Bool {
        let envelope = try ResponsesWebSocketRequest.Envelope(frame, maximumBytes: limits.maxFrameBytes)
        guard
            envelope.fields[OpenAIResponsesCreatedEvent.Key.type.rawValue]?.string
                == ResponsesWebSocketContract.Event.steer.rawValue, supported
        else { return false }
        let steering = try ResponsesWebSocketSteering(envelope)
        guard count < limits.maxQueuedRequests, steering.body.count <= limits.maxQueuedBytes - bytes else {
            throw ResponsesWebSocketFailure(
                status: 429, code: "too_many_pending_steers", message: "Steering queue is full")
        }
        count += 1
        bytes += steering.body.count
        input.yield(steering)
        return true
    }

    mutating func complete(bytes: Int) {
        count -= 1
        self.bytes -= bytes
    }
}
