import Foundation
import LittleSwitchCommon
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native Responses WebSocket policies", .timeLimit(.minutes(1)))
struct ResponsesUpstreamPolicyTests {
    @Test("Automatic successors retain provider admission and provider-owned authentication")
    func admittedChain() async throws {
        let fixture = try managedFixture()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let traffic = TrafficTestRecorder()
        let harness = try NativeResponsesSessionHarness(websocket: websocket, fixture: fixture, traffic: traffic)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(try request(fixture, input: "first"))
        try await websocket.waitForRequests(1)
        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 1)
        let handshake = try #require(await websocket.handshakes.first)
        #expect(handshake.headers["x-api-key"] == ["synthetic-provider"])
        #expect(handshake.headers["authorization"].isEmpty)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.created")
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#)
        try await websocket.waitForRequests(2)
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        try await websocket.publish(
            #"{"type":"response.incomplete","response":{"id":"r1","output":[],"incomplete_details":{"reason":"steered"}}}"#
        )
        _ = try await harness.events.wait(type: "response.incomplete")
        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 1)
        #expect(await fixture.state.sessionRequestCount == 1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r2","output":[]}}"#)
        try await websocket.publish(
            #"{"type":"response.completed","response":{"id":"r2","output":[{"type":"reasoning","id":"reasoning2","summary":[],"encrypted_content":"opaque"}]}}"#
        )
        let completed = try await harness.events.wait(type: "response.completed")
        let wrapped = try #require(
            completed["response"]?.object?["output"]?.array?.first?.object?["encrypted_content"]?.string)
        let provenance = try #require(JSONValue.parse(wrapped).object)
        let provider = try #require(fixture.snapshot.providers.first)
        #expect(provenance["provider_id"]?.string == provider.id.uuidString)
        #expect(provenance["account_id"] == nil)
        _ = try await eventually(description: "chain permit released") {
            await fixture.state.requestPoolSnapshot().totalRunning == 0 ? true : nil
        }
        #expect(await fixture.state.sessionRequestCount == 1)
        #expect(await websocket.requests.count == 2)
        let annotations = traffic.events.flatMap { $0.annotations ?? [] }
        #expect(annotations.contains { $0.kind == "websocket-steering" && $0.message == "response.steer.submitted" })
        #expect(annotations.contains { $0.kind == "websocket-steering" && $0.message == "response.steer.accepted" })
        harness.input.finish()
        try await valueWithinTimeout(task, description: "admitted steering chain cleanup")
    }

    @Test("Rejected provider tools never reach the client and release the native scope for explicit recovery")
    func toolPolicyRecovery() async throws {
        let fixture = try managedFixture()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket, fixture: fixture)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(try request(fixture, input: "first"))
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        try await websocket.publish(
            #"{"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"bad","call_id":"bad","name":"undeclared","arguments":"{}"}}"#
        )
        _ = try await harness.events.wait(type: "error")
        _ = try await eventually(description: "rejected native provider scope joined") {
            await websocket.activeConnections == 0 ? true : nil
        }
        #expect(try await harness.events.values().allSatisfy { $0["type"] != "response.output_item.added" })
        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 0)
        harness.enqueue(try request(fixture, input: "corrected root"))
        try await websocket.waitForRequests(2)
        #expect(await websocket.connections == 2)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r2","output":[]}}"#, connection: 2)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r2","output":[]}}"#, connection: 2)
        _ = try await harness.events.wait(type: "response.completed")
        harness.input.finish()
        try await valueWithinTimeout(task, description: "policy recovery cleanup")
    }

    @Test("Credential revision changes open a fresh chain with full portable input")
    func credentialRevision() async throws {
        let fixture = try managedFixture()
        let websocket = SyntheticResponsesWebSocketTransport()
        let harness = try NativeResponsesSessionHarness(websocket: websocket, fixture: fixture)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(try request(fixture, input: "first"))
        _ = try await harness.events.wait(type: "response.completed")
        let provider = try #require(fixture.snapshot.providers.first)
        try fixture.secrets.write("synthetic-rotated", providerID: provider.id)
        _ = await fixture.state.replace(
            providers: [provider], mappings: fixture.snapshot.mappings, credentialChangedProviderIDs: [provider.id])
        harness.enqueue(try request(fixture, input: "second", previous: "resp_1"))
        try await websocket.waitForRequests(2)
        let second = try #require(await websocket.requests.last)
        #expect(second["previous_response_id"] == nil)
        #expect(second["input"]?.array?.count == 2)
        #expect(await websocket.connections == 2)
        #expect(await websocket.handshakes.last?.headers["x-api-key"] == ["synthetic-rotated"])
        harness.input.finish()
        try await valueWithinTimeout(task, description: "credential rotation cleanup")
    }

    @Test("Steering revalidates its original provider before writing", arguments: 0...3)
    func steeringProviderInvalidated(variant: Int) async throws {
        let fixture = try managedFixture()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket, fixture: fixture)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(try request(fixture, input: "first"))
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.created")
        let provider = try #require(fixture.snapshot.providers.first)
        switch variant {
        case 0:
            _ = await fixture.state.replace(
                providers: [provider], mappings: fixture.snapshot.mappings, credentialChangedProviderIDs: [provider.id])
        case 1:
            _ = await fixture.state.routingMutationGuard.begin(providerID: provider.id)
        case 2:
            await fixture.state.stopAdmissions()
        default:
            _ = await fixture.state.replace(providers: [], mappings: [:])
        }
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"must not be submitted"}"#)
        let error = try await harness.events.wait(type: "error")
        #expect(error["error"]?.object?["code"] == "response_not_found")
        #expect(await websocket.requests.count == 1)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "invalidated steering cleanup")
    }

    @Test(
        "An invalidated provider cannot migrate pending steering or submit a tool continuation",
        arguments: [false, true])
    func pendingSteeringProviderInvalidated(forceAdapter: Bool) async throws {
        let fixture = try managedFixture()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket, fixture: fixture)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        var create = try #require(JSONValue.parse(request(fixture, input: "first")).object)
        create["tools"] = [
            [
                "type": "function", "name": "lookup",
                "parameters": ["type": "object", "properties": .object([:])],
            ]
        ]
        harness.enqueue(try encoded(create))
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.created")
        harness.enqueue(#"{"type":"response.steer","previous_response_id":"r1","input":"pending intent"}"#)
        try await websocket.waitForRequests(2)
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        try await websocket.publish(
            encoded([
                "type": "response.completed",
                "response": [
                    "id": "r1",
                    "output": [
                        [
                            "type": "function_call", "id": "item1", "call_id": "call1", "name": "lookup",
                            "arguments": "{}",
                        ]
                    ],
                ],
            ]))
        _ = try await harness.events.wait(type: "response.completed")
        try await websocket.publish(
            encoded([
                "type": "response.steer.pending", "steer": ["id": "s1", "previous_response_id": "r1"],
                "reason": "waiting_for_required_input",
                "required_input": [["type": "function_call_output", "call_id": "call1", "name": "lookup"]],
            ]))
        _ = try await harness.events.wait(type: "response.steer.pending")
        var provider = try #require(fixture.snapshot.providers.first)
        if forceAdapter { provider.responsesWireOverride = .chatCompletions }
        try fixture.secrets.write("synthetic-rotated", providerID: provider.id)
        _ = await fixture.state.replace(
            providers: [provider], mappings: fixture.snapshot.mappings, credentialChangedProviderIDs: [provider.id])
        create["previous_response_id"] = "r1"
        create["input"] = [["type": "function_call_output", "call_id": "call1", "output": "done"]]
        harness.enqueue(try encoded(create))
        let error = try await harness.events.wait(type: "error")
        #expect(error["error"]?.object?["code"] == "pending_steering")
        let message = try #require(error["error"]?.object?["message"]?.string)
        #expect(message.contains("Reconnect"))
        #expect(message.contains("portable history"))
        #expect(message.contains("unapplied steering"))
        #expect(await websocket.requests.count == 2)
        #expect(await websocket.connections == 1)
        #expect(await harness.http.requests.isEmpty)
        _ = try await eventually(description: "pending steering rejection releases admission") {
            await fixture.state.requestPoolSnapshot().totalRunning == 0 ? true : nil
        }
        harness.input.finish()
        try await valueWithinTimeout(task, description: "pending invalidated provider cleanup")
        #expect(await websocket.activeConnections == 0)
    }

    private func request(_ fixture: GatewayFixture, input: String, previous: String? = nil) throws -> String {
        let provider = try #require(fixture.snapshot.providers.first)
        let model = CodexCatalog.slug(for: .init(providerID: provider.id, modelID: "model"), in: [provider])
        var request: JSONObject = ["type": "response.create", "model": .string(model), "input": .string(input)]
        request["previous_response_id"] = previous.map(JSONValue.string)
        return try encoded(request)
    }

    private func encoded(_ fields: JSONObject) throws -> String {
        let data = try JSONValue.object(fields).serializedData()
        return try #require(String(data: data, encoding: .utf8))
    }

    private func managedFixture() throws -> GatewayFixture {
        let provider = Provider(
            name: "Native WS",
            baseURL: "https://synthetic.example/v1",
            authMode: .xAPIKey,
            models: [DiscoveredModel(id: "model")],
            status: .ready,
            maximumParallelRequests: 1,
            responsesWireOverride: .native)
        let mapping = ModelMapping(providerID: provider.id, modelID: "model")
        let snapshot = RoutingSnapshot(
            generation: 1, providers: [provider], mappings: [:], codex: .init(defaultModel: mapping))
        let secrets = MemorySecretStore()
        try secrets.write("synthetic-provider", providerID: provider.id)
        let state = GatewayState(snapshot: snapshot)
        return GatewayFixture(snapshot: snapshot, state: state, secrets: secrets)
    }
}
