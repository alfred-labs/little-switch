import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Native Responses warmup and fallback", .timeLimit(.minutes(1)))
struct ResponsesUpstreamWarmupTests {
    @Test("Warmup reaches the upstream with generate false and the connection remains reusable")
    func warmup() async throws {
        let websocket = SyntheticResponsesWebSocketTransport()
        let harness = try NativeResponsesSessionHarness(websocket: websocket)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-astra","input":"warm","generate":false}"#)
        _ = try await harness.events.wait(type: "response.completed")
        let warmup = try #require(await websocket.requests.first)
        #expect(warmup["generate"] == .boolean(false))
        harness.enqueue(
            #"{"type":"response.create","model":"gpt-6-astra","previous_response_id":"resp_1","input":"go"}"#)
        try await websocket.waitForRequests(2)
        #expect(await websocket.connections == 1)
        #expect(await websocket.requests.last?["generate"] == nil)
        #expect(await websocket.requests.last?["previous_response_id"] == "resp_1")
        harness.input.finish()
        try await valueWithinTimeout(task, description: "warmup cleanup")
    }

    @Test("Unsupported WebSocket warmup never generates through HTTP")
    func unsupportedWarmup() async throws {
        let websocket = RejectingResponsesWebSocketTransport()
        let harness = try NativeResponsesSessionHarness(websocket: websocket)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-astra","input":"warm","generate":false}"#)
        _ = try await harness.events.wait(type: "response.completed")
        #expect(await websocket.attempts == 1)
        #expect(await harness.http.requests.isEmpty)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "unsupported warmup cleanup")
    }

    @Test("A rejected upgrade and its cached warmups never teach Responses support", arguments: [404, 405, 501])
    func unsupportedManagedWarmup(status: Int) async throws {
        let fixture = try await managedFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        let websocket = RejectingResponsesWebSocketTransport(status: status)
        let harness = try NativeResponsesSessionHarness(
            websocket: websocket, fixture: fixture, clock: ResolverTestClock())
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        #expect(await fixture.state.responsesCapabilities.verdict(for: provider.id) == nil)
        for streamID in ["A", "B"] {
            harness.enqueue(
                #"{"type":"response.create","stream_id":"\#(streamID)","model":"example/model","input":"warm","generate":false}"#
            )
            let completed = try await harness.events.wait(type: "response.completed", streamID: streamID)
            #expect(completed["response"]?.object?["status"] == "completed")
            #expect(completed["response"]?.object?["output"] == .array([]))
            #expect(await fixture.state.responsesCapabilities.verdict(for: provider.id) == nil)
        }
        #expect(await websocket.attempts == 1)
        #expect(await harness.http.requests.isEmpty)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "managed unsupported warmup cleanup")
    }

    @Test("Real WebSocket responses teach native support, including prewarm replies", arguments: [false, true])
    func managedSuccess(generate: Bool) async throws {
        let fixture = try await managedFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        let websocket = SyntheticResponsesWebSocketTransport()
        let harness = try NativeResponsesSessionHarness(
            websocket: websocket, fixture: fixture, clock: ResolverTestClock())
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        #expect(await fixture.state.responsesCapabilities.verdict(for: provider.id) == nil)
        harness.enqueue(
            #"{"type":"response.create","model":"example/model","input":"warm","generate":\#(generate)}"#)
        _ = try await harness.events.wait(type: "response.completed")
        #expect(await fixture.state.responsesCapabilities.verdict(for: provider.id) == true)
        #expect(await websocket.requests.count == 1)
        #expect(await websocket.requests.first?["generate"] == (generate ? nil : .boolean(false)))
        #expect(await harness.http.requests.isEmpty)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "managed WebSocket success cleanup")
    }

    @Test("A custom-tool projection warmup does not teach native support")
    func projectedWarmup() async throws {
        let fixture = try await managedFixture(customTools: true)
        let provider = try #require(fixture.snapshot.providers.first)
        let websocket = SyntheticResponsesWebSocketTransport()
        let harness = try NativeResponsesSessionHarness(
            websocket: websocket, fixture: fixture, clock: ResolverTestClock())
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(
            #"{"type":"response.create","model":"example/model","input":"warm","generate":false,"tools":[{"type":"custom","name":"exec"}]}"#
        )
        let completed = try await harness.events.wait(type: "response.completed")
        #expect(completed["response"]?.object?["output"] == .array([]))
        #expect(await fixture.state.responsesCapabilities.verdict(for: provider.id) == nil)
        #expect(await websocket.connections == 0)
        #expect(await harness.http.requests.isEmpty)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "projected warmup cleanup")
    }

    @Test("The continuation's adapter warmup bypasses model exchange and capability learning")
    func adapterWarmup() async throws {
        let fixture = try await managedFixture(adapter: true)
        let provider = try #require(fixture.snapshot.providers.first)
        let websocket = SyntheticResponsesWebSocketTransport()
        let harness = try NativeResponsesSessionHarness(
            websocket: websocket, fixture: fixture, clock: ResolverTestClock())
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","model":"example/model","input":"warm","generate":false}"#)
        let completed = try await harness.events.wait(type: "response.completed")
        #expect(completed["response"]?.object?["status"] == "completed")
        #expect(completed["response"]?.object?["output"] == .array([]))
        #expect(await fixture.state.responsesCapabilities.verdict(for: provider.id) == nil)
        #expect(await websocket.connections == 0)
        #expect(await harness.http.requests.isEmpty)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "adapter warmup cleanup")
    }

    @Test("An unsupported upgrade falls back before submitting a model request")
    func fallback() async throws {
        let websocket = RejectingResponsesWebSocketTransport()
        let fixture = try GatewayTests().makeFixture()
        let http = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                chunks: [
                    "data: {\"type\":\"response.created\",\"response\":{\"id\":\"r1\",\"output\":[]}}\n\n",
                    "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"r1\",\"output\":[]}}\n\n",
                ])
        ])
        let responder = GatewayResponder(
            state: fixture.state, transport: http, secretStore: fixture.secrets, requiredAuthorityPort: nil)
        let session = ResponsesWebSocketSession(
            responder: responder, request: webSocketHTTPRequest(), upstreamTransport: websocket)
        let (messages, input) = AsyncStream<Data>.makeStream()
        let events = WebSocketEventRecorder()
        let task = Task { try await session.run(messages: messages) { await events.append($0) } }
        defer {
            input.finish()
            task.cancel()
        }
        input.yield(Data(#"{"type":"response.create","model":"gpt-6-astra","input":"go"}"#.utf8))
        _ = try await events.wait(type: "response.completed")
        #expect(await websocket.attempts == 1)
        #expect(await http.requests.count == 1)
        input.finish()
        try await valueWithinTimeout(task, description: "safe HTTP fallback cleanup")
    }

    private func managedFixture(adapter: Bool = false, customTools: Bool = false) async throws -> GatewayFixture {
        let provider = Provider(
            name: "Example",
            baseURL: "https://provider.example",
            authMode: .none,
            models: [DiscoveredModel(id: "model", supportsImageInput: true)],
            status: .ready,
            responsesWireOverride: adapter ? .chatCompletions : nil)
        let snapshot = RoutingSnapshot(generation: 0, providers: [provider], mappings: [:])
        let cache = CustomToolCapabilityCache()
        if customTools {
            let key = CustomToolCapabilityKey(
                providerID: provider.id,
                modelID: "model",
                endpoint: "https://provider.example/v1/responses",
                wire: "responses")
            _ = try await cache.mode(for: key) { .functionEnvelope }
        }
        return GatewayFixture(
            snapshot: snapshot,
            state: GatewayState(snapshot: snapshot, customToolCapabilities: cache),
            secrets: MemorySecretStore())
    }
}

private actor RejectingResponsesWebSocketTransport: UpstreamWebSocketTransport {
    private(set) var attempts = 0
    private let status: Int

    init(status: Int = 404) { self.status = status }

    func withConnection(
        _ request: UpstreamWebSocketRequest,
        operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void
    ) async throws {
        attempts += 1
        throw UpstreamWebSocketFailure(
            kind: .upgradeRejected,
            response: .init(
                head: .init(version: .http1_1, status: .init(statusCode: status)),
                bodyPrefix: Data(),
                bodyState: .complete))
    }
    func shutdown() async throws {}
}
