import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Native upstream session admission", .timeLimit(.minutes(1)))
struct ResponsesUpstreamAdmissionTests {
    @Test("A finished session rejects an exchange before opening a connection")
    func finishedSession() async throws {
        let websocket = SyntheticResponsesWebSocketTransport()
        let session = ResponsesUpstreamSession(transport: websocket, limits: .init()) { _ in }
        await session.finish()
        let request = HTTPClientRequest(url: "https://synthetic.example/v1/responses")
        let body = Data(#"{"model":"model","input":"go"}"#.utf8)
        let turn = turn(body: body)
        let exchange = Task {
            try await session.exchange(turn: turn, request: request, body: body, policy: policy())
        }
        defer { exchange.cancel() }
        await #expect(throws: CancellationError.self) {
            _ = try await valueWithinTimeout(
                exchange, timeout: .milliseconds(100), description: "exchange after upstream session finish")
        }
        #expect(await websocket.connections == 0)
    }

    @Test(
        "Rejected informational, successful and redirect upgrades use cached HTTP fallback",
        arguments: [100, 102, 200, 204, 302, 307, 400, 404, 405, 426, 501])
    func unsupportedUpgrade(status: Int) async throws {
        let websocket = PolicyRejectingWebSocketTransport(status: status)
        let session = ResponsesUpstreamSession(transport: websocket, limits: .init()) { _ in }
        let runner = Task { await session.run() }
        defer { runner.cancel() }
        let request = HTTPClientRequest(url: "https://synthetic.example/v1/responses")
        let body = Data(#"{"model":"model","input":"go"}"#.utf8)
        for _ in 0..<2 {
            let response = try await session.exchange(
                turn: turn(body: body), request: request, body: body, policy: policy())
            #expect(response == nil)
        }
        #expect(await websocket.attempts == 1)
        await session.finish()
        try await valueWithinTimeout(runner, description: "unsupported upgrade cleanup")
    }

    @Test(
        "Authentication, rate and server upgrade failures retain their origin",
        arguments: [401, 403, 429, 500, 502, 503])
    func preservedUpgradeFailure(status: Int) async throws {
        let websocket = PolicyRejectingWebSocketTransport(status: status)
        let session = ResponsesUpstreamSession(transport: websocket, limits: .init()) { _ in }
        let runner = Task { await session.run() }
        defer { runner.cancel() }
        let request = HTTPClientRequest(url: "https://synthetic.example/v1/responses")
        let body = Data(#"{"model":"model","input":"go"}"#.utf8)
        for _ in 0..<2 {
            let response = try #require(
                await session.exchange(turn: turn(body: body), request: request, body: body, policy: policy()))
            #expect(response.status.code == UInt(status))
            #expect(response.headers["retry-after"] == ["7"])
            #expect(Data(try await response.body.collect(upTo: 1_024).readableBytesView) == websocket.body)
        }
        #expect(await websocket.attempts == 2)
        await session.finish()
        try await valueWithinTimeout(runner, description: "origin upgrade failure cleanup")
    }

    @Test(
        "An upgrade GET never teaches native Responses capability",
        arguments: [200, 302, 401, 403, 429, 500, 501, 502, 503])
    func upgradeDoesNotTeachCapability(status: Int) async throws {
        let fixture = try steeringProjectionFixture(acceptsImages: false)
        let provider = try #require(fixture.snapshot.providers.first)
        let websocket = PolicyRejectingWebSocketTransport(status: status)
        let http = RecordingGatewayTransport(responses: [
            response(status: .serviceUnavailable, body: #"{"error":{"message":"upstream unavailable"}}"#)
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
        input.yield(try steeringProjectionCreate(fixture))
        let error = try await events.wait(type: "error")
        let fallsBack = [200, 302, 501].contains(status)
        #expect(error["status"] == .integer(fallsBack ? 503 : status))
        #expect(await http.requests.count == (fallsBack ? 1 : 0))
        #expect(await fixture.state.responsesCapabilities.verdict(for: provider.id) == nil)
        input.finish()
        try await valueWithinTimeout(task, description: "upgrade capability cleanup")
    }

    private func turn(body: Data) -> ResponsesWebSocketTurn {
        .init(id: UUID(), streamID: nil, body: body, generate: true, previousResponseID: nil, replacesHistory: true)
    }

    private func policy() -> ResponsesUpstreamPolicy {
        .init(provider: nil, observeControl: { _ in }, validateProvider: {})
    }
}

private actor PolicyRejectingWebSocketTransport: UpstreamWebSocketTransport {
    let status: Int
    let body = Data(#"{"error":{"message":"upgrade origin"}}"#.utf8)
    private(set) var attempts = 0

    init(status: Int) { self.status = status }

    func withConnection(
        _ request: UpstreamWebSocketRequest,
        operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void
    ) async throws {
        attempts += 1
        throw UpstreamWebSocketFailure(
            kind: .upgradeRejected,
            response: .init(
                head: .init(version: .http1_1, status: .init(statusCode: status), headers: ["retry-after": "7"]),
                bodyPrefix: body,
                bodyState: .complete))
    }

    func shutdown() async throws {}
}
