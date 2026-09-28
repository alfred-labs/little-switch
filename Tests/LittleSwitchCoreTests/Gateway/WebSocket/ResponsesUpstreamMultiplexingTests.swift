import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native upstream multiplexing", .timeLimit(.minutes(1)))
struct ResponsesUpstreamMultiplexingTests {
    @Test("Concurrent native lanes keep continuations and forked checkpoints on their own connections")
    func isolatedContinuationAndFork() async throws {
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        try Self.enqueue(harness, stream: "A", text: "alpha-root")
        try await websocket.waitForRequests(1)
        try Self.enqueue(harness, stream: "B", text: "beta-root")
        try await websocket.waitForRequests(2)
        #expect(await websocket.connections == 2)
        #expect(await websocket.activeConnections == 2)
        let alphaOutput = Self.output(id: "item-alpha", text: "alpha-output")
        let betaOutput = Self.output(id: "item-beta", text: "beta-output")
        try await Self.publish(websocket, connection: 1, type: "response.created", id: "alpha")
        try await Self.publish(websocket, connection: 2, type: "response.created", id: "beta")
        try await Self.publish(websocket, connection: 2, type: "response.completed", id: "beta", output: [betaOutput])
        let beta = try await Self.terminal(harness.events, stream: "B", id: "beta")
        #expect(beta["response"]?.object?["output"] == .array([betaOutput]))
        #expect(
            try await harness.events.values().contains {
                $0["type"] == "response.completed" && $0["stream_id"] == "A"
            } == false)
        try await Self.publish(websocket, connection: 1, type: "response.completed", id: "alpha", output: [alphaOutput])
        let alpha = try await Self.terminal(harness.events, stream: "A", id: "alpha")
        #expect(alpha["response"]?.object?["output"] == .array([alphaOutput]))

        try Self.enqueue(harness, stream: "A", text: "alpha-next", previous: "alpha")
        try await websocket.waitForRequests(3)
        try Self.enqueue(harness, stream: "B", text: "beta-fork", previous: "alpha")
        try await websocket.waitForRequests(4)
        let requests = await websocket.requests
        try #require(requests.count == 4)
        #expect(requests[2]["previous_response_id"] == "alpha")
        #expect(requests[2]["input"] == .array([["role": "user", "content": "alpha-next"]]))
        #expect(requests[3]["previous_response_id"] == nil)
        #expect(
            requests[3]["input"]
                == .array([
                    ["role": "user", "content": "alpha-root"], alphaOutput,
                    ["role": "user", "content": "beta-fork"],
                ]))
        #expect(requests.allSatisfy { $0["stream_id"] == nil })
        #expect(await websocket.connections == 2)
        let forkOutput = Self.output(id: "item-fork", text: "fork-output")
        try await Self.publish(websocket, connection: 2, type: "response.created", id: "fork")
        try await Self.publish(websocket, connection: 2, type: "response.completed", id: "fork", output: [forkOutput])
        let fork = try await Self.terminal(harness.events, stream: "B", id: "fork")
        #expect(fork["response"]?.object?["output"] == .array([forkOutput]))
        let nextOutput = Self.output(id: "item-next", text: "next-output")
        try await Self.publish(websocket, connection: 1, type: "response.created", id: "next")
        try await Self.publish(websocket, connection: 1, type: "response.completed", id: "next", output: [nextOutput])
        let next = try await Self.terminal(harness.events, stream: "A", id: "next")
        #expect(next["response"]?.object?["output"] == .array([nextOutput]))
        #expect(try await harness.events.values().allSatisfy { $0["type"] != "error" })
        #expect(await harness.http.requests.isEmpty)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "both native lanes joined")
        #expect(await websocket.activeConnections == 0)
    }

    @Test("A response identifier owned by two native connections cannot receive steering")
    func ambiguousResponseIdentifier() async throws {
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        try Self.enqueue(harness, stream: "A", text: "alpha-root")
        try await websocket.waitForRequests(1)
        try Self.enqueue(harness, stream: "B", text: "beta-root")
        try await websocket.waitForRequests(2)
        try await Self.publish(websocket, connection: 1, type: "response.created", id: "collision")
        try await Self.publish(websocket, connection: 2, type: "response.created", id: "collision")
        _ = try await harness.events.wait(type: "response.created", streamID: "A")
        _ = try await harness.events.wait(type: "response.created", streamID: "B")
        let before = await websocket.requests
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"collision","input":"must not be sent"}"#)
        let rejection = try await harness.events.wait(type: "error")
        #expect(rejection["status"] == 400)
        #expect(rejection["error"]?.object?["code"] == "response_not_found")
        #expect(await websocket.requests == before)
        #expect(await websocket.activeConnections == 2)
        let alphaOutput = Self.output(id: "item-alpha", text: "alpha-still-live")
        let betaOutput = Self.output(id: "item-beta", text: "beta-still-live")
        try await Self.publish(
            websocket, connection: 1, type: "response.completed", id: "collision", output: [alphaOutput])
        try await Self.publish(
            websocket, connection: 2, type: "response.completed", id: "collision", output: [betaOutput])
        let alpha = try await Self.terminal(harness.events, stream: "A", id: "collision")
        let beta = try await Self.terminal(harness.events, stream: "B", id: "collision")
        #expect(alpha["response"]?.object?["output"] == .array([alphaOutput]))
        #expect(beta["response"]?.object?["output"] == .array([betaOutput]))
        #expect(await websocket.requests == before)
        #expect(await harness.http.requests.isEmpty)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "ambiguous response lanes joined")
        #expect(await websocket.activeConnections == 0)
    }

    private static func enqueue(
        _ harness: NativeResponsesSessionHarness, stream: String, text: String, previous: String? = nil
    ) throws {
        var request: JSONObject = [
            "type": "response.create", "model": "gpt-6-astra", "stream_id": .string(stream),
            "input": [["role": "user", "content": .string(text)]],
        ]
        request["previous_response_id"] = previous.map(JSONValue.string)
        harness.input.yield(try JSONValue.object(request).serializedData())
    }

    private static func output(id: String, text: String) -> JSONValue {
        [
            "id": .string(id), "type": "message", "role": "assistant", "status": "completed",
            "content": [["type": "output_text", "text": .string(text), "annotations": []]],
        ]
    }

    private static func publish(
        _ websocket: SyntheticResponsesWebSocketTransport,
        connection: Int,
        type: String,
        id: String,
        output: [JSONValue] = []
    ) async throws {
        let event: JSONValue = ["type": .string(type), "response": ["id": .string(id), "output": .array(output)]]
        let text = try #require(String(data: event.serializedData(), encoding: .utf8))
        try await websocket.publish(text, connection: connection)
    }

    private static func terminal(
        _ events: WebSocketEventRecorder, stream: String, id: String
    ) async throws -> JSONObject {
        try await eventually(description: "terminal \(id) on native lane \(stream)") {
            try await events.values().first {
                $0["type"] == "response.completed" && $0["stream_id"]?.string == stream
                    && $0["response"]?.object?["id"]?.string == id
            }
        }
    }
}
