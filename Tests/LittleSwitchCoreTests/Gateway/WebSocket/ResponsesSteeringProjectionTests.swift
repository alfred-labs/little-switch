import Foundation
import LittleSwitchCommon
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses steering request projection", .timeLimit(.minutes(1)))
struct ResponsesSteeringProjectionTests {
    @Test("An image steer is rejected before writing on a text-only connection")
    func rejectsImageForTextModel() async throws {
        let fixture = try steeringProjectionFixture(acceptsImages: false)
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket, fixture: fixture)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.input.yield(try steeringProjectionCreate(fixture))
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.created")
        harness.enqueue(imageSteer)
        let error = try await harness.events.wait(type: "error")
        #expect(error["status"] == 400)
        #expect(error["error"]?.object?["code"] == "invalid_input")
        #expect(error["error"]?.object?["param"] == "input")
        #expect(await websocket.requests.count == 1)
        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 1)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.completed")
        harness.input.finish()
        try await valueWithinTimeout(task, description: "rejected image steer cleanup")
    }

    @Test("An image steer reaches an image-capable model unchanged")
    func allowsImageForImageModel() async throws {
        let fixture = try steeringProjectionFixture(acceptsImages: true)
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket, fixture: fixture)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.input.yield(try steeringProjectionCreate(fixture))
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.created")
        harness.enqueue(imageSteer)
        try await websocket.waitForRequests(2)
        #expect(try await websocket.requests.last == JSONValue.parse(imageSteer).object)
        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 1)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "unchanged image steer cleanup")
    }

    @Test("New image observations bind the next create to a fresh projection")
    func refreshedProjection() async throws {
        let initial = try steeringProjectionFixture(acceptsImages: true)
        let provider = try #require(initial.snapshot.providers.first)
        let registry = ModelImageInputRegistry(prober: RegistryTestProber(), admission: RegistryTestAdmission())
        let generation = UUID()
        try await registry.configure(provider: provider, generation: generation)
        let fixture = GatewayFixture(
            snapshot: initial.snapshot,
            state: GatewayState(snapshot: initial.snapshot, imageInputRegistry: registry),
            secrets: initial.secrets)
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket, fixture: fixture)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.input.yield(try steeringProjectionCreate(fixture))
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        _ = try await harness.events.wait(type: "response.completed")
        await registry.record(
            .init(
                key: try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .responses),
                verdict: .unsupported,
                source: .providerRejection,
                observedAt: Date()),
            generation: generation)
        var followup = try #require(JSONValue.parse(steeringProjectionCreate(fixture)).object)
        followup["previous_response_id"] = "r1"
        followup["input"] = "followup"
        harness.input.yield(try JSONValue.object(followup).serializedData())
        try await websocket.waitForRequests(2)
        try #require(await websocket.connections == 2)
        #expect(await websocket.requests.last?["previous_response_id"] == nil)
        #expect(await websocket.requests.last?["input"]?.array?.count == 2)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r2","output":[]}}"#, connection: 2)
        _ = try await eventually(description: "response on refreshed image projection") {
            try await harness.events.values().first { $0["response"]?.object?["id"] == "r2" }
        }
        harness.enqueue(imageSteer.replacingOccurrences(of: "r1", with: "r2"))
        let error = try await harness.events.wait(type: "error")
        #expect(error["error"]?.object?["code"] == "invalid_input")
        #expect(await websocket.requests.count == 2)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "refreshed projection cleanup")
        await registry.shutdown()
    }

    private var imageSteer: String {
        #"{"type":"response.steer","previous_response_id":"r1","input":[{"type":"message","role":"user","content":["#
            + #"{"type":"input_text","text":"Look at this"},"#
            + #"{"type":"input_image","image_url":"https://synthetic.example/image.png"}]}]}"#
    }
}

func steeringProjectionFixture(acceptsImages: Bool) throws -> GatewayFixture {
    let provider = Provider(
        name: "Steering projection",
        baseURL: "https://synthetic.example/v1",
        authMode: .none,
        models: [DiscoveredModel(id: "model", supportsImageInput: acceptsImages)],
        status: .ready,
        maximumParallelRequests: 1,
        responsesWireOverride: .native)
    let mapping = ModelMapping(providerID: provider.id, modelID: "model")
    let snapshot = RoutingSnapshot(
        generation: 1, providers: [provider], mappings: [:], codex: .init(defaultModel: mapping))
    return GatewayFixture(snapshot: snapshot, state: GatewayState(snapshot: snapshot), secrets: MemorySecretStore())
}

func steeringProjectionCreate(_ fixture: GatewayFixture) throws -> Data {
    let provider = try #require(fixture.snapshot.providers.first)
    let model = CodexCatalog.slug(for: .init(providerID: provider.id, modelID: "model"), in: [provider])
    let request: JSONValue = [
        "type": "response.create", "model": .string(model), "input": "initial text",
    ]
    return try request.serializedData()
}
