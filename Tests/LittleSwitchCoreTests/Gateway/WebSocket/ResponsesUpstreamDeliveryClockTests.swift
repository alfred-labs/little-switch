import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native terminal delivery clock", .timeLimit(.minutes(1)))
struct ResponsesUpstreamDeliveryClockTests {
    @Test("Slow accepted-control delivery pauses the remaining continuation budget")
    func bufferedSuccessorAfterControlDelivery() async throws {
        let clock = ResolverTestClock()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let controls = WebSocketEventRecorder()
        let delivered = AsyncTestGate()
        let connection = ResponsesUpstreamConnection(
            key: .init(provider: nil, endpoint: "https://example.invalid/v1/responses", model: "model"),
            request: try UpstreamWebSocketRequest(url: #require(URL(string: "wss://example.invalid/v1/responses"))),
            maximumBytes: 4_096,
            steeringAcknowledgementTimeout: .seconds(5),
            clock: clock
        ) { data in
            await controls.append(data)
            if try JSONValue.parse(data).object?["type"] == "response.steer.accepted" { try await delivered.wait() }
        }
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
        try await connection.steer(
            ResponsesWebSocketSteering(
                .init(
                    Data(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#.utf8),
                    maximumBytes: 4_096)))
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        try await clock.waitForSleeps(1)
        await clock.advance(by: .seconds(4))
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        _ = try await controls.wait(type: "response.steer.accepted")
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r2","output":[]}}"#)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r2","output":[]}}"#)
        await clock.advance(by: .seconds(10))
        await delivered.open()
        let resumed = Task { try await clock.waitForSleeps(2) }
        defer { resumed.cancel() }
        try await valueWithinTimeout(resumed, description: "continuation budget resumes after delivery")
        #expect(await clock.deadlines.last?.offset == .seconds(15))
        try await valueWithinTimeout(consumer, description: "buffered successor after accepted delivery")
        #expect(await connection.usable)
        #expect(await connection.hasPendingSteering == false)
        #expect(try await controls.values().compactMap { $0["type"]?.string } == ["response.steer.accepted"])
        await connection.close()
        try await valueWithinTimeout(runner, description: "accepted delivery cleanup")
    }

    @Test("Slow terminal delivery does not spend the upstream acknowledgement budget")
    func bufferedAcknowledgementAfterDelivery() async throws {
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
        let responseTask = Task {
            try await connection.exchange(
                Data(#"{"type":"response.create","model":"model","input":[]}"#.utf8),
                previousResponseID: nil,
                observeControl: { _ in },
                validateProvider: {})
        }
        defer { responseTask.cancel() }
        let created = AsyncTestGate()
        let received = AsyncTestGate()
        let delivered = AsyncTestGate()
        let consumer = Task {
            let response = try await responseTask.value
            var count = 0
            for try await _ in response.body {
                count += 1
                if count == 1 { await created.open() }
                if count == 2 {
                    await received.open()
                    try await delivered.wait()
                }
            }
        }
        defer { consumer.cancel() }
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        try await created.wait()
        try await connection.steer(
            ResponsesWebSocketSteering(
                .init(
                    Data(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#.utf8),
                    maximumBytes: 4_096)))
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        try await received.wait()
        await clock.advance(by: .seconds(10))
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        #expect(await clock.deadlines.isEmpty)
        await delivered.open()
        try await clock.waitForSleeps(1)
        #expect(await clock.deadlines.first?.offset == .seconds(15))
        _ = try await controls.wait(type: "response.steer.accepted")
        #expect(await connection.usable)
        #expect(try await controls.values().contains { $0["type"] == "response.steer.failed" } == false)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r2","output":[]}}"#)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r2","output":[]}}"#)
        try await valueWithinTimeout(consumer, description: "slow delivery successor")
        await connection.close()
        try await valueWithinTimeout(runner, description: "slow delivery cleanup")
    }
}
