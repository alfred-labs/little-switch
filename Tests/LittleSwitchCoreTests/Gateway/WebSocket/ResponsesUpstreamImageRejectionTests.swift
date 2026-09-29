import Foundation
import LittleSwitchCommon
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native WebSocket image rejection", .timeLimit(.minutes(1)))
struct ResponsesUpstreamImageRejectionTests {
    @Test("An initial image rejection is learned and retries one text-only request")
    func learnsAndRetries() async throws {
        let image = try await GatewayImageFixture.make(wire: .responses)
        let fixture = GatewayFixture(
            snapshot: .init(generation: 0, providers: [image.provider], mappings: [:]),
            state: image.state,
            secrets: MemorySecretStore())
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket, fixture: fixture)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        var request = try #require(JSONValue.parse(image.body).object)
        request["type"] = "response.create"
        harness.input.yield(try JSONValue.object(request).serializedData())
        try await websocket.waitForRequests(1)
        var rejection = try #require(JSONValue.parse(GatewayImageFixture.rejection).object)
        rejection["type"] = "error"
        rejection["status"] = 400
        try await websocket.publish(
            #require(String(data: JSONValue.object(rejection).serializedData(), encoding: .utf8)))
        try await websocket.waitForRequests(2)
        let requests = await websocket.requests
        #expect(try GatewayImageFixture.containsImage(JSONValue.object(requests[0]).serializedData(), wire: .responses))
        #expect(
            try !GatewayImageFixture.containsImage(JSONValue.object(requests[1]).serializedData(), wire: .responses))
        let identifier = await websocket.connections
        try await websocket.publish(
            #"{"type":"response.created","response":{"id":"r2","output":[]}}"#, connection: identifier)
        try await websocket.publish(
            #"{"type":"response.completed","response":{"id":"r2","output":[]}}"#, connection: identifier)
        _ = try await harness.events.wait(type: "response.completed")
        let observations = await image.registry.observations()
        #expect(observations.count == 1)
        #expect(observations.first?.verdict == .unsupported)
        #expect(observations.first?.source == .providerRejection)
        #expect(observations.first?.key.wire == .responses)
        #expect(await image.prober.calls == 0)
        #expect(try await harness.events.values().contains { $0["type"] == "error" } == false)
        // The learned observation also applies to the next independent turn.
        harness.input.yield(try JSONValue.object(request).serializedData())
        try await websocket.waitForRequests(3)
        let next = try #require(await websocket.requests.last)
        #expect(try !GatewayImageFixture.containsImage(JSONValue.object(next).serializedData(), wire: .responses))
        try await websocket.publish(
            #"{"type":"response.created","response":{"id":"r3","output":[]}}"#, connection: identifier)
        try await websocket.publish(
            #"{"type":"response.completed","response":{"id":"r3","output":[]}}"#, connection: identifier)
        _ = try await eventually(description: "learned image policy next turn") {
            try await harness.events.values().first {
                $0["type"] == "response.completed" && $0["response"]?.object?["id"] == "r3"
            }
        }
        #expect(await harness.http.requests.isEmpty)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "native image retry cleanup")
        await image.registry.shutdown()
    }
}
