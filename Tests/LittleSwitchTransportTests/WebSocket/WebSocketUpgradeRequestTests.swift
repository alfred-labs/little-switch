import AsyncHTTPClient
import Foundation
import NIOHTTP1
import Testing

@testable import LittleSwitchTransport

struct WebSocketUpgradeRequestTests {
    @Test(
        "HTTP upgrades preserve escaped paths, queries and explicit ports",
        arguments: [
            ("https://example.test/a%2Fb?value=a%2Bb&value=c", "wss://example.test/a%2Fb?value=a%2Bb&value=c"),
            ("http://example.test:8080/v1/responses?empty=", "ws://example.test:8080/v1/responses?empty="),
            ("https://[::1]:8443/a%252Fb?value=%2F", "wss://[::1]:8443/a%252Fb?value=%2F"),
        ])
    func preservesEncodedTarget(address: String, expected: String) throws {
        let request = try UpstreamWebSocketRequest(upgrading: HTTPClientRequest(url: address))
        #expect(request.url.absoluteString == expected)
    }

    @Test("HTTP upgrades retain provider headers and replace body and handshake fields")
    func selectsHandshakeHeaders() throws {
        var request = HTTPClientRequest(url: "https://example.test/v1/responses")
        request.method = .POST
        let providerHeaders = HTTPHeaders([
            ("Authorization", "fixture-authorization"), ("X-Turn", "one"), ("X-Turn", "two"),
            ("Origin", "https://client.example.test"),
        ])
        request.headers = providerHeaders
        for name in [
            "hOsT", "CoNnEcTiOn", "UpGrAdE", "Content-Length", "Content-Type", "Accept",
            "Transfer-Encoding", "Content-Encoding", "Sec-WebSocket-Key", "Sec-WebSocket-Version",
            "Sec-WebSocket-Protocol", "Sec-WebSocket-Extensions",
        ] {
            request.headers.add(name: name, value: "fixture-value")
            request.headers.add(name: name.lowercased(), value: "duplicate-value")
        }
        let upgrade = try UpstreamWebSocketRequest(upgrading: request)
        #expect(upgrade.headers == providerHeaders)
    }

    @Test(
        "HTTP upgrades reject unsupported destinations without exposing URL credentials",
        arguments: [
            "ftp://example.test/v1/responses", "ws://example.test/v1/responses", "/v1/responses",
            "https://fixture-user:fixture-password@example.test/v1/responses",
            "https://example.test/v1/responses#fragment", "http://example.test:0/v1/responses",
        ])
    func rejectsInvalidDestination(address: String) {
        #expect {
            try UpstreamWebSocketRequest(upgrading: HTTPClientRequest(url: address))
        } throws: { error in
            (error as? UpstreamWebSocketFailure)?.kind == .invalidRequest
                && !String(describing: error).contains("fixture-user")
                && !String(describing: error).contains("fixture-password")
        }
    }

    @Test("HTTP upgrades validate retained headers before connecting")
    func rejectsMalformedProviderHeader() {
        var request = HTTPClientRequest(url: "https://example.test/v1/responses")
        request.headers = HTTPHeaders([("X-Turn", "one\r\nInjected: two")])
        #expect {
            try UpstreamWebSocketRequest(upgrading: request)
        } throws: { error in
            (error as? UpstreamWebSocketFailure)?.kind == .invalidRequest
        }
    }
}
