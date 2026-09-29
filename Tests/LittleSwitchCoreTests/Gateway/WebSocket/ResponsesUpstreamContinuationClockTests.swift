import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Native continuation deadline generations", .timeLimit(.minutes(1)))
struct ResponsesUpstreamContinuationClockTests {
    @Test(
        "Each accepted intent must become pending or failed to release the continuation deadline",
        arguments: [false, true])
    func resolveEveryIntent(resolveSecond: Bool) async throws {
        let clock = ResolverTestClock()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let controls = WebSocketEventRecorder()
        let connection = ResponsesUpstreamConnection(
            key: .init(provider: nil, endpoint: "https://example.invalid/v1/responses", model: "model"),
            request: try UpstreamWebSocketRequest(url: #require(URL(string: "wss://example.invalid/v1/responses"))),
            maximumBytes: 4_096,
            steeringAcknowledgementTimeout: .seconds(5),
            clock: clock
        ) { await controls.append($0) }
        let runner = Task { await connection.run(transport: websocket) }
        defer { runner.cancel() }
        let response = Task {
            try await connection.exchange(
                Data(#"{"type":"response.create","model":"model","input":[]}"#.utf8),
                previousResponseID: nil,
                observeControl: { _ in },
                validateProvider: {})
        }
        defer { response.cancel() }
        let created = AsyncTestGate()
        let consumer = Task {
            for try await _ in try await response.value.body { await created.open() }
        }
        defer { consumer.cancel() }
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        try await created.wait()
        for identifier in ["s1", "s2"] {
            try await connection.steer(
                ResponsesWebSocketSteering(
                    .init(
                        Data(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#.utf8),
                        maximumBytes: 4_096)))
            try await websocket.publish(
                #"{"type":"response.steer.accepted","steer":{"id":"\#(identifier)","previous_response_id":"r1"}}"#)
        }
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        try await clock.waitForSleeps(1)
        try await websocket.publish(
            #"{"type":"response.steer.pending","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        _ = try await controls.wait(type: "response.steer.pending")
        try await websocket.waitForMessages(5)
        if resolveSecond {
            try await websocket.publish(
                #"{"type":"response.steer.failed","steer":{"id":"s2","previous_response_id":"r1"}}"#)
            try await valueWithinTimeout(consumer, description: "resolved automatic continuation")
            await clock.advance(by: .seconds(120))
            // A new exchange is a barrier after the previous body ended; it
            // must remain on this usable connection despite the old timer.
            #expect(await connection.usable)
            let next = Task {
                try await connection.exchange(
                    Data(#"{"type":"response.create","model":"model","previous_response_id":"r1","input":[]}"#.utf8),
                    previousResponseID: "r1",
                    observeControl: { _ in },
                    validateProvider: {})
            }
            defer { next.cancel() }
            try await websocket.waitForRequests(4)
            try await websocket.publish(#"{"type":"response.created","response":{"id":"r2","output":[]}}"#)
            try await websocket.publish(#"{"type":"response.completed","response":{"id":"r2","output":[]}}"#)
            let result = try await valueWithinTimeout(next, description: "next request after pending steer")
            for try await _ in result.body {}
            #expect(await connection.hasPendingSteering == false)
            await connection.close()
        } else {
            await clock.advance(by: .seconds(60))
            try await valueWithinTimeout(consumer, description: "partially pending steering timeout")
            #expect(await connection.usable == false)
        }
        try await valueWithinTimeout(runner, description: "continuation deadline cleanup")
        let failures = try await controls.values().filter { $0["type"] == "response.steer.failed" }
        #expect(failures.compactMap { $0["steer"]?.object?["id"]?.string } == (resolveSecond ? ["s2"] : ["s1", "s2"]))
    }
}
