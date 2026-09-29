import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native close drains", .timeLimit(.minutes(1)))
struct ResponsesUpstreamCloseClockTests {
    @Test("Abort uses the configured close grace and cannot wait forever for downstream")
    func boundedAbort() async throws {
        let clock = ResolverTestClock()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let controls = WebSocketEventRecorder()
        let controlGate = AsyncTestGate()
        var limits = ResponsesWebSocketLimits()
        limits.closeGraceSeconds = 2
        let upstream = ResponsesUpstreamSession(transport: websocket, limits: limits, clock: clock) { data in
            await controls.append(data)
            if try JSONValue.parse(data).object?["type"] == "response.steer.failed" {
                try await controlGate.wait()
            }
        }
        let runner = Task { await upstream.run() }
        defer { runner.cancel() }
        let turn = ResponsesWebSocketTurn(
            id: UUID(),
            streamID: nil,
            body: Data(#"{"model":"model","input":[]}"#.utf8),
            generate: true,
            previousResponseID: nil,
            replacesHistory: false)
        let response = Task {
            try #require(
                await upstream.exchange(
                    turn: turn,
                    request: HTTPClientRequest(url: "https://example.invalid/v1/responses"),
                    body: turn.body,
                    policy: .init(provider: nil, observeControl: { _ in }, validateProvider: {})))
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
        try await upstream.steer(
            ResponsesWebSocketSteering(
                .init(
                    Data(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#.utf8),
                    maximumBytes: 4_096)))
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        _ = try await controls.wait(type: "response.steer.accepted")
        let close = Task { await upstream.abort(turn.id) }
        defer { close.cancel() }
        _ = try await controls.wait(type: "response.steer.failed")
        try await clock.waitForSleeps(1)
        #expect(await clock.deadlines.first?.offset == .seconds(2))
        #expect(await controlGate.isOpen == false)
        await clock.advance(by: .seconds(2))
        try await valueWithinTimeout(close, description: "bounded abort")
        #expect(await websocket.closeRequests == 1)
        await #expect(throws: CancellationError.self) {
            try await valueWithinTimeout(consumer, description: "aborted body")
        }
        await upstream.finish()
        try await valueWithinTimeout(runner, description: "aborted session cleanup")
        #expect(
            try await controls.values().compactMap { $0["type"]?.string } == [
                "response.steer.accepted", "response.steer.failed",
            ])
        #expect(await websocket.activeConnections == 0)
    }
}
