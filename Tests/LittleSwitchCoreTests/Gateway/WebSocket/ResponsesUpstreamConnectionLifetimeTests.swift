import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native upstream connection lifetime", .timeLimit(.minutes(1)))
struct ResponsesUpstreamConnectionLifetimeTests {
    @Test("Cancelling readiness completes without starting or closing the connection")
    func cancelledReadiness() async throws {
        let connection = try makeConnection()
        let entered = AsyncTestGate()
        let completed = AsyncTestGate()
        let task = Task {
            await entered.open()
            do {
                _ = try await connection.exchange(
                    Data(#"{"type":"response.create","model":"gpt-6-astra","input":[]}"#.utf8),
                    previousResponseID: nil,
                    observeControl: { _ in },
                    validateProvider: {})
                await completed.open()
                return false
            } catch {
                await completed.open()
                return error is CancellationError
            }
        }
        try await entered.wait()
        task.cancel()
        let completedBeforeCleanup =
            (try? await completed.wait(timeout: .seconds(1), description: "cancelled readiness")) != nil
        #expect(completedBeforeCleanup)
        if completedBeforeCleanup {
            let websocket = SyntheticResponsesWebSocketTransport()
            let runner = Task { await connection.run(transport: websocket) }
            defer { runner.cancel() }
            let response = try await connection.exchange(
                Data(#"{"type":"response.create","model":"gpt-6-astra","input":[]}"#.utf8),
                previousResponseID: nil,
                observeControl: { _ in },
                validateProvider: {})
            var chunks = 0
            for try await _ in response.body { chunks += 1 }
            #expect(chunks == 2)
            await connection.close()
            try await valueWithinTimeout(runner, description: "connection reused after cancelled readiness")
        }
        // Explicit cleanup also bounds this regression while readiness still
        // ignores cancellation, before the production fix is applied.
        await connection.close()
        #expect(try await valueWithinTimeout(task, description: "readiness cleanup"))
        await connection.close()
    }

    @Test(
        "An unacknowledged submitted steer fails and releases a terminal response", arguments: [false, true])
    func unacknowledgedSteering(withAcceptedSteering: Bool) async throws {
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let controls = WebSocketEventRecorder()
        let connection = try makeConnection { await controls.append($0) }
        let runner = Task { await connection.run(transport: websocket) }
        defer { runner.cancel() }
        let (observations, observer) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingOldest(8))
        defer { observer.finish() }
        let response = try await connection.exchange(
            Data(#"{"type":"response.create","model":"gpt-6-astra","input":[]}"#.utf8),
            previousResponseID: nil,
            observeControl: { observer.yield($0) },
            validateProvider: {})
        let received = AsyncTestGate()
        let completed = AsyncTestGate()
        let consumer = Task {
            for try await _ in response.body { await received.open() }
            await completed.open()
        }
        defer { consumer.cancel() }
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        try await received.wait(description: "created response before steering")
        try await connection.steer(
            makeSteering(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#))
        if withAcceptedSteering {
            try await websocket.publish(
                #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
            _ = try await controls.wait(type: "response.steer.accepted")
            try await connection.steer(
                makeSteering(#"{"type":"response.steer","previous_response_id":"r1","input":"also simpler"}"#))
        }
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        let completedBeforeCleanup =
            (try? await completed.wait(timeout: .seconds(1), description: "steering acknowledgement deadline"))
            != nil
        #expect(completedBeforeCleanup)
        #expect(await connection.hasPendingSteering == false)
        #expect(await connection.usable == false)
        let failures = try await controls.values().filter { $0["type"] == "response.steer.failed" }
        #expect(failures.count == (withAcceptedSteering ? 2 : 1))
        #expect(failures.first?["type"] == "response.steer.failed")
        #expect(failures.first?["steer"]?.object?["previous_response_id"] == "r1")
        #expect(failures.last?["error"]?.object?["code"] == "steering_acknowledgement_timeout")
        if withAcceptedSteering {
            #expect(failures.first?["steer"]?.object?["id"] == "s1")
            #expect(failures.first?["error"]?.object?["code"] == "steering_connection_retired")
        }
        await connection.close()
        runner.cancel()
        _ = try? await valueWithinTimeout(consumer, description: "unacknowledged steering body cleanup")
        try await valueWithinTimeout(runner, description: "unacknowledged steering connection cleanup")
        observer.finish()
        var observed: [String] = []
        for await observation in observations { observed.append(observation) }
        let expected =
            withAcceptedSteering
            ? [
                "response.steer.submitted", "response.steer.accepted", "response.steer.submitted",
                "response.steer.failed", "response.steer.failed",
            ] : ["response.steer.submitted", "response.steer.failed"]
        #expect(observed == expected)
        #expect(await websocket.activeConnections == 0)
    }

    @Test("A configured pending-steer count applies after the ingress queue drains")
    func configuredSteeringCount() async throws {
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        var limits = ResponsesWebSocketLimits()
        limits.maxQueuedRequests = 1
        let harness = try NativeResponsesSessionHarness(websocket: websocket, limits: limits)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-astra","input":"first"}"#)
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.created")
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"first update"}"#)
        try await websocket.waitForRequests(2)
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"second update"}"#)
        let rejection = try? await eventually(timeout: .seconds(1), description: "pending-steer count rejection") {
            try await harness.events.values().first { $0["type"] == "error" }
        }
        #expect(rejection?["status"] == 429)
        #expect(rejection?["error"]?.object?["code"] == "too_many_pending_steers")
        #expect(await websocket.requests.count == 2)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "configured steering count cleanup")
    }

    private func makeConnection(
        control: @escaping @Sendable (Data) async throws -> Void = { _ in }
    ) throws -> ResponsesUpstreamConnection {
        let url = try #require(URL(string: "wss://example.invalid/v1/responses"))
        return ResponsesUpstreamConnection(
            key: .init(provider: nil, endpoint: "https://example.invalid/v1/responses", model: "gpt-6-astra"),
            request: try UpstreamWebSocketRequest(url: url),
            maximumBytes: 4_096,
            steeringAcknowledgementTimeout: .milliseconds(5),
            control: control)
    }

    private func makeSteering(_ text: String) throws -> ResponsesWebSocketSteering {
        try ResponsesWebSocketSteering(.init(Data(text.utf8), maximumBytes: 4_096))
    }
}
