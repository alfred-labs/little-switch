import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Native upstream session lifetime", .timeLimit(.minutes(1)))
struct ResponsesUpstreamLifetimeTests {
    @Test("Closing downstream joins a blocked steering write while other output remains live")
    func blockedSteeringWrite() async throws {
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false, steerGate: AsyncTestGate())
        let harness = try NativeResponsesSessionHarness(websocket: websocket)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-astra","input":"first"}"#)
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.created")
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#)
        try await websocket.waitForRequests(2)
        try await websocket.publish(#"{"type":"response.output_text.delta","delta":"still live"}"#)
        _ = try await harness.events.wait(type: "response.output_text.delta")
        harness.input.finish()
        try await valueWithinTimeout(task, description: "closed downstream during blocked steering write")
        #expect(await websocket.activeConnections == 0)
    }

    @Test("A new explicit root recovers on the same lane after upstream disconnect")
    func explicitRecovery() async throws {
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-astra","input":"first"}"#)
        try await websocket.waitForRequests(1)
        await websocket.disconnect()
        _ = try await harness.events.wait(type: "error")
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-astra","input":"new root"}"#)
        try await websocket.waitForRequests(2)
        #expect(await websocket.connections == 2)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r2","output":[]}}"#, connection: 2)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r2","output":[]}}"#, connection: 2)
        _ = try await harness.events.wait(type: "response.completed")
        harness.input.finish()
        try await valueWithinTimeout(task, description: "recovered native connection cleanup")
    }

    @Test("An uncertain submission is never replayed through WebSocket or HTTP")
    func uncertainSubmission() async throws {
        let websocket = SyntheticResponsesWebSocketTransport(
            sendFailure: .init(submission: .mayHaveBeenSubmitted, cause: .init(kind: .writeFailed)))
        let harness = try NativeResponsesSessionHarness(websocket: websocket)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-astra","input":"one operation"}"#)
        _ = try await harness.events.wait(type: "error")
        #expect(await websocket.requests.count == 1)
        #expect(await websocket.connections == 1)
        #expect(await harness.http.requests.isEmpty)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "uncertain submission cleanup")
    }
}
