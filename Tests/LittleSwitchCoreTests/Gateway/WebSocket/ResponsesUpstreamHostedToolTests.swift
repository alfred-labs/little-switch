import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native steering with hosted tools", .timeLimit(.minutes(1)))
struct ResponsesUpstreamHostedToolTests {
    @Test(
        "Hosted tools do not block automatic continuation for either full or Lite terminals",
        arguments: ["tool_search_call", "shell_call"], [false, true])
    func hostedTool(type: String, lite: Bool) async throws {
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
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
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"continue"}"#)
        try await websocket.waitForRequests(2)
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        let item = Self.hostedItem(type)
        try await websocket.publish(
            Self.encoded([
                "type": "response.output_item.done", "response_id": "r1", "output_index": 0, "item": .object(item),
            ]))
        try await websocket.publish(
            Self.encoded([
                "type": "response.completed",
                "response": ["id": "r1", "output": .array(lite ? [] : [.object(item)])],
            ]))
        let terminal = try await harness.events.wait(type: "response.completed")
        #expect(terminal["response"]?.object?["output"]?.array == [.object(item)])
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r2","output":[]}}"#)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r2","output":[]}}"#)
        _ = try await eventually(description: "successor after hosted tool") {
            try await harness.events.values().contains {
                $0["type"] == "response.completed" && $0["response"]?.object?["id"] == "r2"
            } ? true : nil
        }
        #expect(await websocket.requests.map { $0["type"]?.string } == ["response.create", "response.steer"])
        #expect(await websocket.connections == 1)
        #expect(try await harness.events.values().allSatisfy { $0["type"] != "error" })
        harness.input.finish()
        try await valueWithinTimeout(task, description: "hosted tool steering cleanup")
        #expect(await websocket.activeConnections == 0)
    }

    @Test("Pretty-printed provider JSON becomes valid SSE without losing exact numbers")
    func multilineProviderJSON() async throws {
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-astra","input":"first"}"#)
        try await websocket.waitForRequests(1)
        try await websocket.publish(
            """
            {
              "type": "response.created",
              "response": {"id": "r1", "output": []}
            }
            """)
        _ = try await harness.events.wait(type: "response.created")
        try await websocket.publish(
            """
            {
              "type": "response.completed",
              "response": {"id": "r1", "output": []},
              "opaque": 9007199254740993
            }
            """)
        let terminal = try await harness.events.wait(type: "response.completed")
        #expect(terminal["opaque"] == .integer(9_007_199_254_740_993))
        #expect(await websocket.requests.count == 1)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "multiline upstream cleanup")
        #expect(await websocket.activeConnections == 0)
    }

    private static func hostedItem(_ type: String) -> JSONObject {
        if type == "tool_search_call" {
            return [
                "type": "tool_search_call", "id": "item1", "call_id": .null, "execution": "server",
                "arguments": ["query": "synthetic"], "status": "completed",
            ]
        }
        return [
            "type": "shell_call", "id": "item1", "call_id": "call1", "status": "completed",
            "action": ["commands": ["true"], "max_output_length": .null, "timeout_ms": .null],
            "environment": ["type": "container_reference", "container_id": "container_synthetic"],
        ]
    }

    private static func encoded(_ fields: JSONObject) throws -> String {
        let data = try JSONValue.object(fields).serializedData()
        return try #require(String(data: data, encoding: .utf8))
    }
}
