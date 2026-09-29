import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Steering failure ownership", .timeLimit(.minutes(1)))
struct ResponsesUpstreamSteeringOutcomeTests {
    @Test("Both failure paths restore the steering queue's count and byte budget", arguments: [false, true])
    func completionRestoresQueueBudget(registered: Bool) async throws {
        let envelope = try ResponsesWebSocketRequest.Envelope(
            Data(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#.utf8),
            maximumBytes: 4_096)
        let steering = try ResponsesWebSocketSteering(envelope)
        var limits = ResponsesWebSocketLimits()
        limits.maxQueuedRequests = 1
        limits.maxQueuedBytes = steering.body.count
        let (stream, input) = AsyncStream<ResponsesWebSocketSteering>.makeStream(bufferingPolicy: .bufferingOldest(1))
        defer { input.finish() }
        var iterator = stream.makeAsyncIterator()
        var queue = ResponsesWebSocketSteeringQueue(input: input, limits: limits)
        try queue.enqueue(envelope)
        #expect(throws: ResponsesWebSocketFailure.self) { try queue.enqueue(envelope) }
        _ = try #require(await iterator.next())
        let result: Result<ResponsesSteeringOutcome, any Error> =
            registered
            ? .success(.connectionOwnedFailure)
            : .failure(ResponsesWebSocketFailure(status: 400, code: .invalidInput, message: "Synthetic invalid input"))
        let failure = queue.complete(bytes: steering.body.count, result: result)
        if registered {
            #expect(failure == nil)
        } else {
            #expect(failure?.status == 400)
            #expect(failure?.code == .invalidInput)
        }
        try queue.enqueue(envelope)
        #expect(throws: ResponsesWebSocketFailure.self) { try queue.enqueue(envelope) }
        #expect(try #require(await iterator.next()).body == steering.body)
    }

    @Test("A registered failed write emits one steer failure and no duplicate steering error")
    func failedWriteIsReportedOnce() async throws {
        let websocket = SyntheticResponsesWebSocketTransport(
            automaticReplies: false,
            sendFailure: .init(submission: .mayHaveBeenSubmitted, cause: .init(kind: .writeFailed)),
            successfulRequests: 1)
        let harness = try NativeResponsesSessionHarness(websocket: websocket, clock: ResolverTestClock())
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","stream_id":"A","model":"gpt-6-astra","input":"first"}"#)
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.created", streamID: "A")
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#)
        _ = try await harness.events.wait(type: "error", streamID: "A")
        // The ordered steering writer processes this rejection after the
        // failed write's result. Observing it proves that result was drained.
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"missing","input":"barrier"}"#)
        _ = try await eventually(description: "steering writer completion barrier") {
            try await harness.events.values().first { $0["error"]?.object?["code"] == "steering_not_supported" }
        }
        let values = try await harness.events.values()
        #expect(
            values.compactMap { $0["type"]?.string } == [
                "response.created", "response.steer.failed", "error", "error",
            ])
        let failures = values.filter { $0["type"] == "response.steer.failed" }
        #expect(failures.count == 1)
        #expect(failures.first?["steer"]?.object?["previous_response_id"] == "r1")
        #expect(failures.first?["error"]?.object?["code"] == "steering_connection_retired")
        let unboundErrors = values.filter { $0["type"] == "error" && $0["stream_id"] == nil }
        #expect(unboundErrors.compactMap { $0["error"]?.object?["code"]?.string } == ["steering_not_supported"])
        #expect(values.filter { $0["type"] == "error" && $0["stream_id"] == "A" }.count == 1)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "single failed-write signal cleanup")
    }

    @Test("A pre-submission projection rejection emits one error and frees the steering queue")
    func validationRejectionReleasesQueue() async throws {
        let fixture = try steeringProjectionFixture(acceptsImages: false)
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        var limits = ResponsesWebSocketLimits()
        limits.maxQueuedRequests = 1
        let harness = try NativeResponsesSessionHarness(
            websocket: websocket, fixture: fixture, limits: limits, clock: ResolverTestClock())
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.input.yield(try steeringProjectionCreate(fixture))
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.created")
        harness.enqueue(
            #"{"type":"response.steer","previous_response_id":"r1","input":[{"type":"message","role":"user","content":[{"type":"input_image","image_url":"https://synthetic.example/image.png"}]}]}"#
        )
        let rejected = try await harness.events.wait(type: "error")
        #expect(rejected["status"] == 400)
        #expect(rejected["error"]?.object?["code"] == "invalid_input")
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"valid text"}"#)
        try await websocket.waitForRequests(2)
        #expect(await websocket.requests.last?["input"] == "valid text")
        #expect(try await harness.events.values().filter { $0["type"] == "error" }.count == 1)
        #expect(try await harness.events.values().contains { $0["type"] == "response.steer.failed" } == false)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "pre-submission queue cleanup")
    }
}
