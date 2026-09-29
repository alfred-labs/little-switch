import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native checkpoint failure isolation", .timeLimit(.minutes(1)))
struct ResponsesWebSocketCheckpointFailureTests {
    @Test("Shared checkpoint budget exhaustion aborts only its lane and permits later requests")
    func budgetFailureIsScoped() async throws {
        var limits = ResponsesWebSocketLimits()
        limits.maxActiveBytes = 4_096
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket, limits: limits)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        for stream in ["A", "B"] {
            let request: JSONValue = [
                "type": "response.create", "stream_id": .string(stream), "model": "gpt-6-astra",
                "input": .string(String(repeating: stream, count: 700)),
            ]
            harness.input.yield(try request.serializedData())
            try await websocket.waitForRequests(stream == "A" ? 1 : 2)
        }
        #expect(await websocket.activeConnections == 2)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"a","output":[]}}"#)
        try await websocket.publish(
            #"{"type":"response.created","response":{"id":"b","output":[]}}"#, connection: 2)
        let completed: JSONValue = [
            "type": "response.completed",
            "response": [
                "id": "a",
                "output": [
                    [
                        "type": "message", "role": "assistant",
                        "content": [["type": "output_text", "text": .string(String(repeating: "x", count: 700))]],
                    ]
                ],
            ],
        ]
        let encoded = try completed.serializedData()
        let terminal = try #require(String(data: encoded, encoding: .utf8))
        try await websocket.publish(terminal)
        let failure = try await harness.events.wait(type: "error", streamID: "A")
        #expect(failure["status"] == 502)
        #expect(failure["error"]?.object?["code"] == "invalid_response")
        _ = try await eventually(description: "only failed native lane closed") {
            await websocket.activeConnections == 1 ? true : nil
        }
        try await websocket.publish(
            #"{"type":"response.completed","response":{"id":"b","output":[]}}"#, connection: 2)
        _ = try await harness.events.wait(type: "response.completed", streamID: "B")
        harness.enqueue(#"{"type":"response.create","stream_id":"A","model":"gpt-6-astra","input":"retry"}"#)
        try await websocket.waitForRequests(3)
        try await websocket.publish(
            #"{"type":"response.created","response":{"id":"recovered","output":[]}}"#, connection: 3)
        try await websocket.publish(
            #"{"type":"response.completed","response":{"id":"recovered","output":[]}}"#, connection: 3)
        let recovered = try await harness.events.wait(type: "response.completed", streamID: "A")
        #expect(recovered["response"]?.object?["id"] == "recovered")
        #expect(try await harness.events.values().filter { $0["type"] == "error" }.count == 1)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "checkpoint failure isolation cleanup")
        #expect(await websocket.activeConnections == 0)
    }

    @Test("A socket write failure at a native checkpoint still terminates the session")
    func terminalWriteRemainsFatal() async throws {
        let websocket = SyntheticResponsesWebSocketTransport()
        let harness = try NativeResponsesSessionHarness(websocket: websocket)
        let task = Task {
            try await harness.session.run(messages: harness.messages) { data in
                if try JSONValue.parse(data).object?["type"] == "response.completed" {
                    throw GatewayTestError.failure
                }
            }
        }
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","stream_id":"A","model":"gpt-6-astra","input":"hello"}"#)
        await #expect(throws: GatewayTestError.failure) {
            try await valueWithinTimeout(task, description: "fatal checkpoint socket write")
        }
        #expect(await websocket.activeConnections == 0)
    }
}
