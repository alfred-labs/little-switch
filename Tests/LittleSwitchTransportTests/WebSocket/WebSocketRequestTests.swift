import Foundation
import NIOHTTP1
import Testing

@testable import LittleSwitchTransport

struct WebSocketRequestTests {
    @Test(arguments: [
        "https://example.test/v1/responses",
        "ws://user:password@example.test/v1/responses",
        "wss://example.test/v1/responses#fragment",
        "ws:///v1/responses",
        "ws://example.test:0/v1/responses",
    ])
    func rejectsAmbiguousOrUnsupportedDestination(value: String) throws {
        let url = try #require(URL(string: value))
        #expect(throws: UpstreamWebSocketFailure.self) {
            try UpstreamWebSocketRequest(url: url)
        }
    }

    @Test(arguments: [
        "Host", "Connection", "Upgrade", "Sec-WebSocket-Key", "Sec-WebSocket-Version",
        "Content-Length", "Transfer-Encoding", "Sec-WebSocket-Protocol", "Sec-WebSocket-Extensions",
    ])
    func rejectsCallerOwnedUpgradeHeaders(name: String) throws {
        let url = try #require(URL(string: "wss://example.test/v1/responses"))
        #expect(throws: UpstreamWebSocketFailure.self) {
            try UpstreamWebSocketRequest(url: url, headers: HTTPHeaders([(name.lowercased(), "value")]))
        }
    }

    @Test func preservesExplicitHeadersAndEncodedTarget() throws {
        let url = try #require(URL(string: "wss://example.test/a%2Fb?value=a%2Bb&value=c"))
        let headers = HTTPHeaders([("Authorization", "test-token"), ("X-Turn", "one"), ("X-Turn", "two")])
        let request = try UpstreamWebSocketRequest(url: url, headers: headers)
        #expect(request.url.absoluteString == "wss://example.test/a%2Fb?value=a%2Bb&value=c")
        #expect(request.headers == headers)
        #expect(!request.headers.contains(name: "Origin"))
    }

    @Test func rejectsInvalidResourceLimitsBeforeOpeningConnections() {
        #expect(throws: UpstreamWebSocketFailure.self) {
            try NIOUpstreamWebSocketTransport(configuration: .init(handshakeTimeout: .zero))
        }
        #expect(throws: UpstreamWebSocketFailure.self) {
            try NIOUpstreamWebSocketTransport(configuration: .init(maximumInboundMessageBytes: 0))
        }
        #expect(throws: UpstreamWebSocketFailure.self) {
            try NIOUpstreamWebSocketTransport(configuration: .init(maximumQueuedBytes: -1))
        }
        #expect(throws: UpstreamWebSocketFailure.self) {
            try NIOUpstreamWebSocketTransport(configuration: .init(pingInterval: .zero))
        }
    }
}
