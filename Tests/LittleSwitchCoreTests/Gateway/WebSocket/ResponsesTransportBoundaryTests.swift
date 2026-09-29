import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Responses transport boundary", .timeLimit(.minutes(1)))
struct ResponsesTransportBoundaryTests {
    @Test(
        "HTTP request upgrades preserve the encoded target and provider headers",
        arguments: [
            ("https://example.test/a%2Fb?value=a%2Bb&value=c", "wss://example.test/a%2Fb?value=a%2Bb&value=c"),
            ("http://example.test:8080/v1/responses?empty=", "ws://example.test:8080/v1/responses?empty="),
        ])
    func upgradedRequest(endpoint: String, expectedAddress: String) async throws {
        let websocket = SyntheticResponsesWebSocketTransport()
        let session = ResponsesUpstreamSession(transport: websocket, limits: .init()) { _ in }
        let running = Task { await session.run() }
        defer { running.cancel() }
        let body = Data(#"{"model":"provider-model","input":[]}"#.utf8)
        let turn = ResponsesWebSocketTurn(
            id: UUID(),
            streamID: "lane",
            body: body,
            generate: true,
            previousResponseID: nil,
            replacesHistory: false)
        var request = HTTPClientRequest(url: endpoint)
        request.method = .POST
        let providerHeaders = HTTPHeaders([
            ("Authorization", "fixture-authorization"), ("X-Turn", "one"), ("X-Turn", "two"),
        ])
        request.headers = providerHeaders
        for name in [
            "Host", "Connection", "Upgrade", "Content-Length", "Content-Type", "Accept",
            "Transfer-Encoding", "Content-Encoding", "Sec-WebSocket-Key", "Sec-WebSocket-Version",
            "Sec-WebSocket-Protocol", "Sec-WebSocket-Extensions",
        ] {
            request.headers.add(name: name, value: "fixture-value")
        }
        let response = try #require(
            await session.exchange(
                turn: turn,
                request: request,
                body: body,
                policy: .init(provider: nil, observeControl: { _ in }, validateProvider: {})))
        let bytes = try await response.body.collect(upTo: 4_096)
        let upgrade = try #require(await websocket.handshakes.first)
        #expect(upgrade.url.absoluteString == expectedAddress)
        #expect(upgrade.headers == providerHeaders)
        #expect(
            String(buffer: bytes)
                == "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_1\",\"output\":[]}}\n\n"
                + "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\",\"output\":[]}}\n\n")
        await session.finish()
        await running.value
        #expect(await websocket.activeConnections == 0)
    }
}
