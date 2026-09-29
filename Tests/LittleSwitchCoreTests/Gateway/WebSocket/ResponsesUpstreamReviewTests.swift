import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Native upstream review regressions", .timeLimit(.minutes(1)))
struct ResponsesUpstreamReviewTests {
    @Test("Accepted steering without an automatic successor retires the upstream")
    func missingSuccessor() async throws {
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let clock = ResolverTestClock()
        var limits = ResponsesWebSocketLimits()
        limits.steeringAcknowledgementTimeout = .seconds(5)
        let harness = try NativeResponsesSessionHarness(websocket: websocket, limits: limits, clock: clock)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        try await startAcceptedSteering(harness, websocket: websocket)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.completed")
        try await clock.waitForSleeps(1)
        await clock.advance(by: .seconds(5))
        let failed = try await harness.events.wait(type: "response.steer.failed")
        #expect(failed["steer"]?.object?["id"] == "s1")
        #expect(failed["error"]?.object?["code"] == "steering_connection_retired")
        harness.input.finish()
        try await valueWithinTimeout(task, description: "missing successor cleanup")
    }

    @Test(
        "Unapplied steering is failed before a disconnected or failed turn",
        arguments: ["disconnect", "response.failed", "error"])
    func abandonedSteering(ending: String) async throws {
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        try await startAcceptedSteering(harness, websocket: websocket)
        if ending == "response.failed" {
            try await websocket.publish(#"{"type":"response.failed","response":{"id":"r1","output":[]}}"#)
        } else if ending == "error" {
            try await websocket.publish(
                #"{"type":"error","code":"upstream_error","message":"Synthetic stream failure"}"#)
        } else {
            await websocket.disconnect()
        }
        let terminal = ending == "response.failed" ? "response.failed" : "error"
        _ = try await harness.events.wait(type: terminal)
        let events = try await harness.events.values()
        #expect(
            events.compactMap { $0["type"]?.string } == [
                "response.created", "response.steer.accepted", "response.steer.failed", terminal,
            ])
        let failures = events.filter { $0["type"] == "response.steer.failed" }
        #expect(failures.count == 1)
        #expect(failures.first?["steer"]?.object?["id"] == "s1")
        harness.input.finish()
        try await valueWithinTimeout(task, description: "abandoned steering cleanup")
    }

    @Test("Session teardown never writes failure controls for accepted steering", arguments: [false, true])
    func teardown(cancellation: Bool) async throws {
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        try await startAcceptedSteering(harness, websocket: websocket)
        if cancellation { task.cancel() } else { harness.input.finish() }
        do {
            try await valueWithinTimeout(task, description: "session teardown with accepted steering")
        } catch is CancellationError {
            #expect(cancellation)
        }
        #expect(
            try await harness.events.values().compactMap { $0["type"]?.string } == [
                "response.created", "response.steer.accepted",
            ])
        #expect(await websocket.activeConnections == 0)
    }

    @Test("A failed write signals accepted and submitted steering before either turn error")
    func failedWrite() async throws {
        let websocket = SyntheticResponsesWebSocketTransport(
            automaticReplies: false,
            sendFailure: .init(submission: .mayHaveBeenSubmitted, cause: .init(kind: .writeFailed)),
            successfulRequests: 2)
        let harness = try NativeResponsesSessionHarness(websocket: websocket)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        try await startAcceptedSteering(harness, websocket: websocket)
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"another"}"#)
        _ = try await harness.events.wait(type: "error")
        let values = try await harness.events.values()
        #expect(
            values.prefix(4).compactMap { $0["type"]?.string } == [
                "response.created", "response.steer.accepted", "response.steer.failed", "response.steer.failed",
            ])
        let failures = values.filter { $0["type"] == "response.steer.failed" }
        #expect(failures.count == 2)
        #expect(failures.first?["steer"]?.object?["id"] == "s1")
        #expect(failures.last?["steer"]?.object?["id"] == nil)
        #expect(failures.allSatisfy { $0["error"]?.object?["code"] == "steering_connection_retired" })
        harness.input.finish()
        try await valueWithinTimeout(task, description: "failed steering write cleanup")
        #expect(await websocket.activeConnections == 0)
    }

    @Test("An error before response creation is an HTTP request rejection")
    func requestRejection() async throws {
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let connection = ResponsesUpstreamConnection(
            key: .init(provider: nil, endpoint: "https://example.invalid/v1/responses", model: "model"),
            request: try UpstreamWebSocketRequest(url: #require(URL(string: "wss://example.invalid/v1/responses"))),
            maximumBytes: 4_096
        ) { _ in }
        let runner = Task { await connection.run(transport: websocket) }
        defer { runner.cancel() }
        let request = Task {
            try await connection.exchange(
                Data(#"{"type":"response.create","model":"model","input":[]}"#.utf8),
                previousResponseID: nil,
                observeControl: { _ in },
                validateProvider: {})
        }
        defer { request.cancel() }
        try await websocket.waitForRequests(1)
        try await websocket.publish(
            #"{"type":"error","status":400,"error":{"type":"invalid_request_error","code":"invalid_image","message":"Image inputs are not supported","param":"input"}}"#
        )
        let response = try await valueWithinTimeout(request, description: "early request rejection")
        #expect(response.status.code == 400)
        #expect(response.headers["content-type"] == ["application/json"])
        let bytes = try await response.body.collect(upTo: 4_096)
        let expected: JSONValue = [
            "error": [
                "type": "invalid_request_error", "code": "invalid_image", "message": "Image inputs are not supported",
                "param": "input",
            ]
        ]
        #expect((try? JSONValue.parse(Data(buffer: bytes))) == expected)
        #expect(await connection.usable)
        let retry = Task {
            try await connection.exchange(
                Data(#"{"type":"response.create","model":"model","input":[]}"#.utf8),
                previousResponseID: nil,
                observeControl: { _ in },
                validateProvider: {})
        }
        defer { retry.cancel() }
        try await websocket.waitForRequests(2)
        let created = #"{"type":"response.created","response":{"id":"r2","output":[]}}"#
        let error = #"{"type":"error","code":"upstream_error","message":"Synthetic stream failure"}"#
        try await websocket.publish(created)
        try await websocket.publish(error)
        let stream = try await valueWithinTimeout(retry, description: "exchange after initial rejection")
        #expect(stream.status.code == 200)
        #expect(stream.headers["content-type"] == ["text/event-stream"])
        let streamBytes = try await stream.body.collect(upTo: 4_096)
        #expect(String(buffer: streamBytes) == "data: \(created)\n\ndata: \(error)\n\n")
        #expect(await websocket.connections == 1)
        await connection.close()
        try await valueWithinTimeout(runner, description: "early rejection cleanup")
    }

    private func startAcceptedSteering(
        _ harness: NativeResponsesSessionHarness, websocket: SyntheticResponsesWebSocketTransport
    ) async throws {
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-astra","input":"first"}"#)
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.created")
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#)
        try await websocket.waitForRequests(2)
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        _ = try await harness.events.wait(type: "response.steer.accepted")
    }
}
