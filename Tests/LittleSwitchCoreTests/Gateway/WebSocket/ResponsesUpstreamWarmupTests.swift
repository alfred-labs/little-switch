import AsyncHTTPClient
import Foundation
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
}

private actor RejectingResponsesWebSocketTransport: UpstreamWebSocketTransport {
    private(set) var attempts = 0
    func withConnection(
        _ request: UpstreamWebSocketRequest,
        operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void
    ) async throws {
        attempts += 1
        throw UpstreamWebSocketFailure(
            kind: .upgradeRejected,
            response: .init(
                head: .init(version: .http1_1, status: .notFound), bodyPrefix: Data(), bodyState: .complete))
    }
    func shutdown() async throws {}
}
