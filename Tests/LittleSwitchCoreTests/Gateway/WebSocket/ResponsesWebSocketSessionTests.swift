import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchCommon
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Responses WebSocket session", .timeLimit(.minutes(1)))
struct ResponsesWebSocketSessionTests {
    @Test("Read errors reach the WebSocket transport so it can choose the protocol close status")
    func readFailure() async throws {
        let harness = try WebSocketSessionHarness(transport: WebSocketSessionTransport())
        let (messages, input) = AsyncThrowingStream<Data, any Error>.makeStream()
        input.finish(throwing: GatewayTestError.failure)
        await #expect(throws: GatewayTestError.failure) {
            try await harness.session.run(messages: messages) { _ in }
        }
    }

    @Test("A blocked lane permits another lane to finish and forks keep a frozen parent")
    func parallelTurnsAndFork() async throws {
        let transport = WebSocketSessionTransport()
        let harness = try WebSocketSessionHarness(transport: transport)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","stream_id":"A","model":"gpt-6","input":"slow"}"#)
        _ = try await eventually(description: "first upstream turn") {
            await transport.requests.isEmpty ? nil : true
        }
        harness.enqueue(
            #"{"type":"response.create","stream_id":"A","model":"gpt-6","input":"queued","previous_response_id":"r1"}"#)
        harness.enqueue(#"{"type":"response.create","stream_id":"B","model":"gpt-6","input":"fast"}"#)
        let fast = try await harness.events.wait(type: "response.completed", streamID: "B")
        #expect(fast["response"]?.object?["id"] == .string("r2"))
        #expect(await transport.requests.count == 2)
        harness.enqueue(
            #"{"type":"response.create","stream_id":"fork","model":"gpt-6","input":"branch","previous_response_id":"r2"}"#
        )
        _ = try await harness.events.wait(type: "response.completed", streamID: "fork")
        #expect(await transport.requests.count == 3)
        await transport.slow.open()
        _ = try await eventually(description: "both FIFO turns") {
            try await harness.events.values().filter {
                $0["type"] == .string("response.completed") && $0["stream_id"] == .string("A")
            }.count == 2 ? true : nil
        }
        let requests = await transport.requests
        #expect(requests.count == 4)
        let fork = try #require(JSONValue.parse(requests[2].body).object)
        let continuation = try #require(JSONValue.parse(requests[3].body).object)
        #expect(fork["previous_response_id"] == nil)
        #expect(continuation["previous_response_id"] == nil)
        #expect(fork["input"]?.array?.count == 3)
        #expect(continuation["input"]?.array?.count == 3)
        #expect(fork["input"]?.array?.first?.object?["content"]?.array?.first?.object?["text"] == .string("fast"))
        #expect(
            continuation["input"]?.array?.first?.object?["content"]?.array?.first?.object?["text"] == .string("slow"))
        harness.input.finish()
        try await valueWithinTimeout(task, description: "closed session")
    }

    @Test("Malformed requests and failed providers leave independent lanes usable")
    func errorsAreScoped() async throws {
        let harness = try WebSocketSessionHarness(transport: WebSocketSessionTransport())
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue("not JSON")
        _ = try await harness.events.wait(type: "error")
        harness.enqueue(
            #"{"type":"response.create","stream_id":"missing","model":"gpt-6","input":[],"previous_response_id":"unknown"}"#
        )
        let missing = try await harness.events.wait(type: "error", streamID: "missing")
        #expect(missing["error"]?.object?["code"] == .string("previous_response_not_found"))
        harness.enqueue(#"{"type":"response.create","stream_id":"bad","model":"gpt-6","input":"malformed-stream"}"#)
        let failed = try await harness.events.wait(type: "error", streamID: "bad")
        #expect(failed["status"] == .integer(502))
        harness.enqueue(#"{"type":"response.create","stream_id":"good","model":"gpt-6","input":"recovered"}"#)
        _ = try await harness.events.wait(type: "response.completed", streamID: "good")
        harness.input.finish()
        try await valueWithinTimeout(task, description: "session after failures")
    }

    @Test("Closing or cancelling a connection cancels its pending upstream turn", arguments: [false, true])
    func cancelsUpstream(cancel: Bool) async throws {
        let transport = WebSocketSessionTransport()
        let harness = try WebSocketSessionHarness(transport: transport)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","model":"gpt-6","input":"slow"}"#)
        _ = try await eventually(description: "blocked upstream") { await transport.requests.count == 1 ? true : nil }
        if cancel { task.cancel() } else { harness.input.finish() }
        _ = try? await valueWithinTimeout(task, description: "upstream cancellation")
        #expect(await transport.wasCancelled)
    }

    @Test("Connection expiry sends a bounded error and finishes the session")
    func expires() async throws {
        let harness = try WebSocketSessionHarness(transport: WebSocketSessionTransport(), lifetime: .milliseconds(1))
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        try await valueWithinTimeout(task, description: "expired connection")
        let error = try await harness.events.wait(type: "error")
        #expect(error["error"]?.object?["code"] == .string("websocket_connection_limit_reached"))
    }

    @Test("The protocol expiry uses the same configured lifetime as the socket watchdog")
    func configuredLifetime() async throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: WebSocketSessionTransport(),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil)
        var limits = ResponsesWebSocketLimits()
        limits.connectionLifetimeSeconds = 0
        let session = ResponsesWebSocketSession(responder: responder, request: webSocketHTTPRequest(), limits: limits)
        let (messages, input) = AsyncStream<Data>.makeStream()
        let events = WebSocketEventRecorder()
        let task = Task { try await session.run(messages: messages) { await events.append($0) } }
        defer {
            input.finish()
            task.cancel()
        }
        try await valueWithinTimeout(task, description: "configured WebSocket lifetime")
        let error = try await events.wait(type: "error")
        #expect(error["error"]?.object?["code"] == .string("websocket_connection_limit_reached"))
    }

    @Test("A failed socket write cancels the whole connection without trapping a worker")
    func socketFailure() async throws {
        let harness = try WebSocketSessionHarness(transport: WebSocketSessionTransport())
        let task = Task {
            try await harness.session.run(messages: harness.messages) { _ in throw GatewayTestError.failure }
        }
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","model":"gpt-6","input":"fast"}"#)
        await #expect(throws: GatewayTestError.failure) {
            try await valueWithinTimeout(task, description: "failed socket")
        }
    }
}

struct WebSocketSessionHarness: Sendable {
    let messages: AsyncStream<Data>
    let input: AsyncStream<Data>.Continuation
    let session: ResponsesWebSocketSession
    let events = WebSocketEventRecorder()

    init(transport: any UpstreamTransport, lifetime: Duration = .seconds(60)) throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = GatewayResponder(
            state: fixture.state, transport: transport, secretStore: fixture.secrets, requiredAuthorityPort: nil)
        (messages, input) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(128))
        session = ResponsesWebSocketSession(
            responder: responder, request: webSocketHTTPRequest(), lifetime: lifetime)
    }

    func start() -> Task<Void, any Error> {
        Task { try await session.run(messages: messages) { await events.append($0) } }
    }

    func enqueue(_ message: String) { input.yield(Data(message.utf8)) }
}

func webSocketHTTPRequest(headers: HTTPFields = [:]) -> Request {
    Request(
        head: HTTPRequest(
            method: .get, scheme: "http", authority: "localhost", path: "/v1/responses", headerFields: headers),
        body: .init(buffer: ByteBuffer()))
}

actor WebSocketSessionTransport: UpstreamTransport {
    let slow = AsyncTestGate()
    private(set) var requests: [RecordedGatewayRequest] = []
    private(set) var wasCancelled = false

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        let body = try await recordedBody(request.body)
        let text = try #require(String(data: body, encoding: .utf8))
        requests.append(.init(url: request.url, headers: request.headers, body: body))
        let identifier = "r\(requests.count)"
        if requests.count == 1, text.contains("slow") {
            do { try await slow.wait() } catch {
                wasCancelled = true
                throw error
            }
        }
        if text.contains("malformed-stream") {
            return streamingResponse(
                status: .ok, headers: ["content-type": "text/event-stream"], chunks: ["data: {}\n\n"])
        }
        let response =
            #"{"id":"\#(identifier)","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"answer"}]}]}"#
        return streamingResponse(
            status: .ok,
            headers: ["content-type": "text/event-stream"],
            chunks: [
                "data: {\"type\":\"response.created\",\"response\":{\"id\":\"\(identifier)\"}}\n\n",
                "data: {\"type\":\"response.completed\",\"response\":\(response)}\n\n",
            ])
    }
}
