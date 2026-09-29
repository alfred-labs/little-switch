import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native upstream steering", .timeLimit(.minutes(1)))
struct ResponsesUpstreamSteeringTests {
    @Test(
        "Accepted steering crosses a published terminal into an automatic successor",
        arguments: ["response.completed", "response.incomplete"])
    func automaticContinuation(originalTerminal: String) async throws {
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
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#)
        try await websocket.waitForRequests(2)
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        try await websocket.publish(
            "{\"type\":\"\(originalTerminal)\",\"response\":{\"id\":\"r1\",\"output\":[],\"incomplete_details\":{\"reason\":\"steered\"}}}"
        )
        _ = try await harness.events.wait(type: originalTerminal)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r2","output":[]}}"#)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r2","output":[]}}"#)
        _ = try await eventually(description: "automatic successor terminal") {
            try await harness.events.values().contains {
                $0["type"] == "response.completed" && $0["response"]?.object?["id"] == "r2"
            } ? true : nil
        }
        #expect(await websocket.requests.count == 2)
        #expect(await websocket.connections == 1)
        // A different model cannot use opaque upstream state. Full replay must
        // retain the applied update once, between the original turn and this one.
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-sol","previous_response_id":"r2","input":"third"}"#)
        try await websocket.waitForRequests(3)
        let replay = try #require(await websocket.requests.last)
        #expect(replay["previous_response_id"] == nil)
        let input = try #require(replay["input"]?.array)
        #expect(input.count == 3)
        #expect(input[1].object?["content"] == "smaller")
        harness.input.finish()
        try await valueWithinTimeout(task, description: "steering cleanup")
        #expect(await websocket.activeConnections == 0)
    }

    @Test("Failed steering does not terminate the original response or enter replay")
    func failedSteering() async throws {
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
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"discard me"}"#)
        try await websocket.waitForRequests(2)
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        try await websocket.publish(
            #"{"type":"response.steer.failed","steer":{"id":"s1","previous_response_id":"r1","input":"discard me"},"#
                + #""error":{"code":"steering_not_supported","message":"Synthetic failure"}}"#
        )
        _ = try await harness.events.wait(type: "response.steer.failed")
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.completed")
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-sol","previous_response_id":"r1","input":"next"}"#)
        try await websocket.waitForRequests(3)
        let replay = try #require(await websocket.requests.last)
        #expect(replay["input"]?.array?.count == 2)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "failed steering cleanup")
    }

    @Test(
        "Tool-result create can arrive before or after the pending notification", arguments: [false, true],
        [false, true])
    func toolPending(earlyCreate: Bool, liteTerminal: Bool) async throws {
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","stream_id":"tools","model":"gpt-6-astra","input":"first"}"#)
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.created", streamID: "tools")
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#)
        try await websocket.waitForRequests(2)
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        if liteTerminal {
            try await websocket.publish(
                #"{"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"item1","call_id":"call1","name":"lookup","arguments":"{}"}}"#
            )
            try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        } else {
            try await websocket.publish(
                #"{"type":"response.completed","response":{"id":"r1","output":[{"type":"function_call","id":"item1","call_id":"call1","name":"lookup","arguments":"{}"}]}}"#
            )
        }
        _ = try await harness.events.wait(type: "response.completed", streamID: "tools")
        let continuation =
            #"{"type":"response.create","stream_id":"tools","model":"gpt-6-astra","previous_response_id":"r1","instructions":"New settings","#
            + #""input":[{"type":"function_call_output","call_id":"call1","output":"done"}]}"#
        harness.enqueue(
            #"{"type":"response.create","stream_id":"tools","model":"gpt-6-sol","previous_response_id":"r1","input":"incompatible"}"#
        )
        let rejection = try await eventually(description: "pending steering rejection") {
            try await harness.events.values().first { $0["type"] == "error" }
        }
        #expect(rejection["error"]?.object?["code"] == "pending_steering")
        #expect(rejection["stream_id"] == "tools")
        #expect(await websocket.requests.count == 2)
        if earlyCreate {
            harness.enqueue(continuation)
            try await websocket.waitForRequests(3)
        } else {
            try await websocket.publish(
                #"{"type":"response.steer.pending","steer":{"id":"s1","previous_response_id":"r1"},"#
                    + #""reason":"waiting_for_required_input","#
                    + #""required_input":[{"type":"function_call_output","call_id":"call1","name":"lookup"}]}"#
            )
            _ = try await harness.events.wait(type: "response.steer.pending")
            harness.enqueue(continuation)
            try await websocket.waitForRequests(3)
        }
        let request = try #require(await websocket.requests.last)
        #expect(request["previous_response_id"] == "r1")
        #expect(request["instructions"] == "New settings")
        #expect(request["input"]?.array?.count == 1)
        #expect(await websocket.connections == 1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r2","output":[]}}"#)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r2","output":[]}}"#)
        _ = try await eventually(description: "tool successor terminal") {
            try await harness.events.values().contains {
                $0["response"]?.object?["id"] == "r2" && $0["type"] == "response.completed"
            } ? true : nil
        }
        harness.enqueue(
            #"{"type":"response.create","stream_id":"tools","model":"gpt-6-sol","previous_response_id":"r2","input":"last"}"#
        )
        try await websocket.waitForRequests(4)
        let replay = try #require(await websocket.requests.last?["input"]?.array)
        #expect(replay.count == 5)
        #expect(replay[2].object?["type"] == "function_call_output")
        #expect(replay[3].object?["content"] == "smaller")
        harness.input.finish()
        try await valueWithinTimeout(task, description: "tool pending cleanup")
    }
}
