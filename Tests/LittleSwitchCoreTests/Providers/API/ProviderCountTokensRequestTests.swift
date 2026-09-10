import AsyncHTTPClient
import Foundation
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Provider count-tokens requests")
struct ProviderCountTokensRequestTests {
    @Test("Bearer requests reuse the safe forwarding boundary")
    func bearerRequest() async throws {
        let provider = Provider(
            name: "Example",
            baseURL: "https://inference.example.com/anthropic",
            authMode: .bearer
        )
        let body = Data(#"{"messages":[],"model":"large"}"#.utf8)
        let request = try ProviderRequestBuilder.countTokens(
            provider: provider,
            secret: "selected",
            headers: unsafeForwardingHeaders,
            body: body
        )

        #expect(request.url == "https://inference.example.com/anthropic/v1/messages/count_tokens")
        #expect(request.method == .POST)
        #expect(request.headers["authorization"] == ["Bearer selected"])
        #expect(request.headers["x-api-key"].isEmpty)
        assertSafeHeaders(request.headers)
        #expect(try await requestBody(request) == body)
    }

    @Test("API-key requests replace ambient provider credentials")
    func apiKeyRequest() async throws {
        let provider = Provider(
            name: "Private",
            baseURL: "https://provider.example.com/base",
            authMode: .xAPIKey
        )
        let body = Data(#"{"messages":[],"model":"model"}"#.utf8)
        let request = try ProviderRequestBuilder.countTokens(
            provider: provider,
            secret: "selected-key",
            headers: unsafeForwardingHeaders,
            body: body
        )

        #expect(request.url == "https://provider.example.com/base/v1/messages/count_tokens")
        #expect(request.method == .POST)
        #expect(request.headers["x-api-key"] == ["selected-key"])
        #expect(request.headers["authorization"].isEmpty)
        assertSafeHeaders(request.headers)
        #expect(try await requestBody(request) == body)
    }

    private var unsafeForwardingHeaders: HTTPHeaders {
        [
            "authorization": "incoming",
            "x-api-key": "incoming-key",
            "cookie": "private",
            "host": "localhost:11436",
            "connection": "x-private-hop",
            "x-private-hop": "private",
            "content-length": "42",
            "content-encoding": "zstd",
            "content-type": "application/json",
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "token-counting-2024-11-01",
        ]
    }

    private func assertSafeHeaders(_ headers: HTTPHeaders) {
        #expect(headers["cookie"].isEmpty)
        #expect(headers["host"].isEmpty)
        #expect(headers["connection"].isEmpty)
        #expect(headers["x-private-hop"].isEmpty)
        #expect(headers["content-length"].isEmpty)
        #expect(headers["content-encoding"].isEmpty)
        #expect(headers["content-type"] == ["application/json"])
        #expect(headers["anthropic-version"] == ["2023-06-01"])
        #expect(headers["anthropic-beta"] == ["token-counting-2024-11-01"])
    }

    private func requestBody(_ request: HTTPClientRequest) async throws -> Data {
        var data = Data()
        if let body = request.body {
            for try await buffer in body {
                data.append(contentsOf: buffer.readableBytesView)
            }
        }
        return data
    }
}
