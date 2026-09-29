import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native steering acknowledgement safety", .timeLimit(.minutes(1)))
struct ResponsesUpstreamAckSafetyTests {
    @Test("An acknowledged automatic successor arriving before the deadline remains usable")
    func timelyAcknowledgement() async throws {
        let clock = ResolverTestClock()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let controls = WebSocketEventRecorder()
        let connection = try makeConnection(timeout: .seconds(5), clock: clock) { await controls.append($0) }
        let runner = Task { await connection.run(transport: websocket) }
        defer { runner.cancel() }
        let responseTask = Task {
            try await connection.exchange(
                create, previousResponseID: nil, observeControl: { _ in }, validateProvider: {})
        }
        defer { responseTask.cancel() }
        let received = AsyncTestGate()
        let consumer = Task {
            let response = try await responseTask.value
            for try await _ in response.body { await received.open() }
        }
        defer { consumer.cancel() }
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        try await received.wait(description: "created response before acknowledged steering")
        try await connection.steer(steering())
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        _ = try await controls.wait(type: "response.steer.accepted")
        try await clock.waitForSleeps(1)
        await clock.advance(by: .seconds(4))
        #expect(await connection.usable)
        #expect(await connection.hasPendingSteering)
        #expect(try await controls.values().count == 1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r2","output":[]}}"#)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r2","output":[]}}"#)
        try await valueWithinTimeout(consumer, description: "acknowledged steering successor")
        await clock.advance(by: .seconds(10))
        #expect(await connection.hasPendingSteering == false)
        await connection.close()
        try await valueWithinTimeout(runner, description: "acknowledged steering cleanup")
    }

    @Test("Retirement closes the reader and denies another turn while failure controls are being written")
    func lateAcknowledgement() async throws {
        let clock = ResolverTestClock()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let controls = WebSocketEventRecorder()
        let controlGate = AsyncTestGate()
        let connection = try makeConnection(timeout: .seconds(5), clock: clock) {
            await controls.append($0)
            try await controlGate.wait()
        }
        let runner = Task { await connection.run(transport: websocket) }
        defer { runner.cancel() }
        let responseTask = Task {
            try await connection.exchange(
                create, previousResponseID: nil, observeControl: { _ in }, validateProvider: {})
        }
        defer { responseTask.cancel() }
        let received = AsyncTestGate()
        let consumer = Task {
            let response = try await responseTask.value
            for try await _ in response.body { await received.open() }
        }
        defer { consumer.cancel() }
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        try await received.wait(description: "created response before late acknowledgement")
        try await connection.steer(steering())
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        try await clock.waitForSleeps(1)
        await clock.advance(by: .seconds(5))
        _ = try await controls.wait(type: "response.steer.failed")
        #expect(await connection.usable == false)
        #expect(await connection.hasPendingSteering == false)
        #expect(await websocket.activeConnections == 0)
        await #expect {
            _ = try await connection.exchange(
                create, previousResponseID: "r1", observeControl: { _ in }, validateProvider: {})
        } throws: { error in
            (error as? UpstreamWebSocketFailure)?.kind == .connectionClosing
        }
        #expect(await websocket.requests.count == 2)
        await controlGate.open()
        try await valueWithinTimeout(consumer, description: "body after late acknowledgement")
        try await valueWithinTimeout(runner, description: "retired connection after late acknowledgement")
        #expect(try await controls.values().count == 1)
        #expect(await websocket.activeConnections == 0)
    }

    @Test("Timeout releases a named lane and replays its completed history on a new connection")
    func portableReplayAfterTimeout() async throws {
        let clock = ResolverTestClock()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        var limits = ResponsesWebSocketLimits()
        limits.steeringAcknowledgementTimeout = .seconds(5)
        let harness = try NativeResponsesSessionHarness(websocket: websocket, limits: limits, clock: clock)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","stream_id":"A","model":"gpt-6-astra","input":"first"}"#)
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.created", streamID: "A")
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"unapplied"}"#)
        try await websocket.waitForRequests(2)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.completed", streamID: "A")
        try await clock.waitForSleeps(1)
        await clock.advance(by: .seconds(5))
        _ = try await harness.events.wait(type: "response.steer.failed")
        harness.enqueue(
            #"{"type":"response.create","stream_id":"A","model":"gpt-6-astra","previous_response_id":"r1","input":"second"}"#
        )
        try await websocket.waitForRequests(3)
        #expect(await websocket.connections == 2)
        let request = try #require(await websocket.requests.last)
        #expect(request["previous_response_id"] == nil)
        let input = try #require(request["input"]?.array)
        #expect(
            input == [
                ["type": "message", "role": "user", "content": [["type": "input_text", "text": "first"]]],
                ["type": "message", "role": "user", "content": [["type": "input_text", "text": "second"]]],
            ])
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r2","output":[]}}"#, connection: 2)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r2","output":[]}}"#, connection: 2)
        _ = try await eventually(description: "portable replay terminal") {
            try await harness.events.values().first {
                $0["type"] == "response.completed" && $0["response"]?.object?["id"] == "r2"
            }
        }
        #expect(try await harness.events.values().contains { $0["type"] == "error" } == false)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "portable replay after steering timeout cleanup")
    }

    @Test(
        "A tool terminal waits for submitted steering to be acknowledged",
        arguments: [
            #"{"type":"response.completed","response":{"id":"r1","output":[{"type":"function_call","id":"item1","call_id":"call1","name":"lookup","arguments":"{}"}]}}"#
        ])
    func finalTerminalWaitsForAcknowledgement(terminal: String) async throws {
        let clock = ResolverTestClock()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let controls = WebSocketEventRecorder()
        let connection = try makeConnection(timeout: .seconds(5), clock: clock) { await controls.append($0) }
        let runner = Task { await connection.run(transport: websocket) }
        defer { runner.cancel() }
        let responseTask = Task {
            try await connection.exchange(
                create, previousResponseID: nil, observeControl: { _ in }, validateProvider: {})
        }
        defer { responseTask.cancel() }
        let received = AsyncTestGate()
        let terminalReceived = AsyncTestGate()
        let consumer = Task {
            let response = try await responseTask.value
            var chunks = 0
            for try await _ in response.body {
                chunks += 1
                if chunks == 1 { await received.open() } else { await terminalReceived.open() }
            }
        }
        defer { consumer.cancel() }
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        try await received.wait(description: "created response before final terminal")
        try await connection.steer(steering())
        try await websocket.publish(terminal)
        try await terminalReceived.wait(description: "terminal delivered before acknowledgement")
        #expect(await connection.hasPendingSteering)
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        _ = try await controls.wait(type: "response.steer.accepted")
        try await valueWithinTimeout(consumer, description: "acknowledged tool terminal")
        await connection.close()
        try await valueWithinTimeout(consumer, description: "final terminal body cleanup")
        try await valueWithinTimeout(runner, description: "final terminal connection cleanup")
    }

    private var create: Data {
        Data(#"{"type":"response.create","model":"gpt-6-astra","input":[]}"#.utf8)
    }

    private func steering() throws -> ResponsesWebSocketSteering {
        try ResponsesWebSocketSteering(
            .init(
                Data(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#.utf8),
                maximumBytes: 4_096))
    }

    private func makeConnection(
        timeout: Duration,
        clock: ResolverTestClock = ResolverTestClock(),
        control: @escaping @Sendable (Data) async throws -> Void
    ) throws -> ResponsesUpstreamConnection {
        let url = try #require(URL(string: "wss://example.invalid/v1/responses"))
        return ResponsesUpstreamConnection(
            key: .init(provider: nil, endpoint: "https://example.invalid/v1/responses", model: "gpt-6-astra"),
            request: try UpstreamWebSocketRequest(url: url),
            maximumBytes: 4_096,
            steeringAcknowledgementTimeout: timeout,
            clock: clock,
            control: control)
    }
}
