import AsyncHTTPClient
import Foundation
import HTTPTypes
import LittleSwitchTransport
import LittleSwitchWire
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Native upstream Responses sessions", .timeLimit(.minutes(1)))
struct ResponsesUpstreamSessionTests {
    @Test("Native turns reuse a connection and send only incremental input")
    func incremental() async throws {
        let websocket = SyntheticResponsesWebSocketTransport()
        let fixture = try GatewayTests().makeFixture()
        let http = RecordingGatewayTransport(responses: [])
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
        input.yield(Data(#"{"type":"response.create","model":"gpt-6-astra","input":"first"}"#.utf8))
        _ = try await events.wait(type: "response.completed")
        input.yield(
            Data(
                #"{"type":"response.create","model":"gpt-6-astra","previous_response_id":"resp_1","input":"second"}"#
                    .utf8))
        _ = try await eventually(description: "second native response") {
            try await events.values().filter { $0["type"] == "response.completed" }.count == 2 ? true : nil
        }
        let requests = await websocket.requests
        #expect(await websocket.connections == 1)
        #expect(await http.requests.isEmpty)
        try #require(requests.count == 2)
        #expect(requests[1]["previous_response_id"] == "resp_1")
        #expect(requests[1]["input"]?.array?.count == 1)
        #expect(requests[1]["stream"] == nil)
        input.finish()
        try await valueWithinTimeout(task, description: "native session cleanup")
        #expect(await websocket.activeConnections == 0)
    }
}

actor SyntheticResponsesWebSocketTransport: UpstreamWebSocketTransport {
    let automaticReplies: Bool
    let steerGate: AsyncTestGate?
    let sendFailure: UpstreamWebSocketSendFailure?
    let successfulRequests: Int
    private(set) var requests: [JSONObject] = []
    private(set) var connections = 0
    private(set) var activeConnections = 0
    private(set) var processedMessages = 0
    private(set) var closeRequests = 0
    private(set) var handshakes: [UpstreamWebSocketRequest] = []
    private var continuations: [Int: AsyncThrowingStream<UpstreamWebSocketMessage, any Error>.Continuation] = [:]

    init(
        automaticReplies: Bool = true,
        steerGate: AsyncTestGate? = nil,
        sendFailure: UpstreamWebSocketSendFailure? = nil,
        successfulRequests: Int = 0
    ) {
        self.automaticReplies = automaticReplies
        self.steerGate = steerGate
        self.sendFailure = sendFailure
        self.successfulRequests = successfulRequests
    }

    func withConnection(
        _ request: UpstreamWebSocketRequest,
        operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void
    ) async throws {
        connections += 1
        handshakes.append(request)
        let identifier = connections
        activeConnections += 1
        defer { activeConnections -= 1 }
        let (stream, continuation) = AsyncThrowingStream<UpstreamWebSocketMessage, any Error>.makeStream(
            bufferingPolicy: .bufferingOldest(32))
        defer { continuation.finish() }
        continuations[identifier] = continuation
        defer { continuations.removeValue(forKey: identifier) }
        let outbound = SyntheticResponsesOutbound(owner: self, continuation: continuation)
        try await operation(
            .init(
                handshake: .init(version: .http1_1, status: .switchingProtocols),
                inbound: SyntheticResponsesInbound(stream: stream, owner: self),
                outbound: outbound))
    }

    func send(
        _ message: UpstreamWebSocketMessage,
        to continuation: AsyncThrowingStream<UpstreamWebSocketMessage, any Error>.Continuation
    ) async throws {
        guard case .text(let text) = message, let request = try JSONValue.parse(text).object else {
            throw GatewayTestError.failure
        }
        requests.append(request)
        if let sendFailure, requests.count > successfulRequests { throw sendFailure }
        if request["type"] == "response.steer", let steerGate { try await steerGate.wait() }
        guard automaticReplies else { return }
        let response: JSONValue = ["id": .string("resp_\(requests.count)"), "output": []]
        for type in ["response.created", "response.completed"] {
            let event: JSONValue = ["type": .string(type), "response": response]
            let data = try event.serializedData()
            continuation.yield(.text(try #require(String(data: data, encoding: .utf8))))
        }
    }

    func shutdown() async throws {}

    func publish(_ text: String, connection: Int = 1) throws {
        let continuation = try #require(continuations[connection])
        guard case .enqueued = continuation.yield(.text(text)) else { throw GatewayTestError.failure }
    }

    func disconnect(connection: Int = 1) {
        continuations[connection]?.finish(throwing: UpstreamWebSocketFailure(kind: .connectionLost))
    }

    func waitForRequests(_ count: Int) async throws {
        _ = try await eventually(description: "native upstream requests") {
            await self.requests.count >= count ? true : nil
        }
    }

    func didProcessMessage() { processedMessages += 1 }

    func close(_ continuation: AsyncThrowingStream<UpstreamWebSocketMessage, any Error>.Continuation) {
        closeRequests += 1
        continuation.finish()
    }

    func waitForMessages(_ count: Int) async throws {
        _ = try await eventually(description: "processed native upstream messages") {
            await self.processedMessages >= count ? true : nil
        }
    }
}

struct NativeResponsesSessionHarness: Sendable {
    let session: ResponsesWebSocketSession
    let events = WebSocketEventRecorder()
    let messages: AsyncStream<Data>
    let input: AsyncStream<Data>.Continuation
    let http = RecordingGatewayTransport(responses: [])

    init<C: Clock>(
        websocket: any UpstreamWebSocketTransport,
        fixture supplied: GatewayFixture? = nil,
        traffic: any TrafficRecording = NoopTrafficRecorder(),
        limits: ResponsesWebSocketLimits = .init(),
        clock: C = ContinuousClock()
    ) throws where C.Duration == Duration {
        let fixture = try supplied ?? GatewayTests().makeFixture()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: http,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: traffic)
        session = ResponsesWebSocketSession(
            responder: responder,
            request: webSocketHTTPRequest(),
            limits: limits,
            upstreamTransport: websocket,
            clock: clock)
        (messages, input) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(128))
    }

    func start() -> Task<Void, any Error> {
        Task { try await session.run(messages: messages) { await events.append($0) } }
    }

    func enqueue(_ text: String) { input.yield(Data(text.utf8)) }
}

private struct SyntheticResponsesInbound: UpstreamWebSocketInbound {
    let stream: AsyncThrowingStream<UpstreamWebSocketMessage, any Error>
    let owner: SyntheticResponsesWebSocketTransport
    func consume(
        _ onMessage: @escaping @Sendable (UpstreamWebSocketMessage) async throws -> Void
    ) async throws -> UpstreamWebSocketPeerClose {
        for try await message in stream {
            try await onMessage(message)
            await owner.didProcessMessage()
        }
        return .init(code: 1_000, reason: nil)
    }
}

private struct SyntheticResponsesOutbound: UpstreamWebSocketOutbound {
    let owner: SyntheticResponsesWebSocketTransport
    let continuation: AsyncThrowingStream<UpstreamWebSocketMessage, any Error>.Continuation
    func send(_ message: UpstreamWebSocketMessage) async throws { try await owner.send(message, to: continuation) }
    func close(code: UInt16, reason: String?) async throws { await owner.close(continuation) }
}
