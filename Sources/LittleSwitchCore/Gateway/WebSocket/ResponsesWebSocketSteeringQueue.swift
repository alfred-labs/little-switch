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

    mutating func enqueue(_ envelope: ResponsesWebSocketRequest.Envelope) throws {
        let steering = try ResponsesWebSocketSteering(envelope)
        guard count < limits.maxQueuedRequests, steering.body.count <= limits.maxQueuedBytes - bytes else {
            throw ResponsesWebSocketFailure(
                status: 429, code: .tooManyPendingSteers, message: "Steering queue is full")
        }
        count += 1
        bytes += steering.body.count
        input.yield(steering)
    }

    /// Queue accounting completes for every writer result, including a failure
    /// already owned by the connection. Only pre-submission rejections need a
    /// separate command error; the original response's error is independent.
    mutating func complete(
        bytes: Int, result: Result<ResponsesSteeringOutcome, any Error>
    ) -> ResponsesWebSocketFailure? {
        count -= 1
        self.bytes -= bytes
        switch result {
        case .success(.forwarded), .success(.connectionOwnedFailure):
            return nil
        case .failure(let error):
            return (error as? ResponsesWebSocketFailure)
                ?? ResponsesWebSocketFailure(status: 502, code: .upstreamError, message: "Could not forward steering")
        }
    }
}
