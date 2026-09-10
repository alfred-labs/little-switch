import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Provider endpoint compatibility")
struct ProviderEndpointTests {
    @Test(
        "Provider URLs normalize safely",
        arguments: [
            ("http://localhost:11434/", "http://localhost:11434"),
            ("http://127.0.0.1:8000/api/", "http://127.0.0.1:8000/api"),
            ("https://API.Z.AI/api/anthropic/", "https://api.z.ai/api/anthropic"),
        ]
    )
    func normalizedURL(input: String, expected: String) throws {
        #expect(try ProviderEndpoint.normalize(input) == expected)
    }

    @Test(
        "Unsafe provider URLs are rejected",
        arguments: [
            "",
            "http://",
            "ftp://localhost/models",
            "http://example.com",
            "https://user:secret@example.com",
            "https://example.com/path?token=x",
            "https://example.com/path#fragment",
        ]
    )
    func rejectedURL(input: String) {
        #expect(throws: ProviderEndpoint.Error.self) {
            try ProviderEndpoint.normalize(input)
        }
    }

    @Test("Endpoint joining preserves a provider base path")
    func joinsEndpoints() throws {
        #expect(
            try ProviderEndpoint.appending("/v1/models", to: "https://api.z.ai/api/anthropic")
                .absoluteString == "https://api.z.ai/api/anthropic/v1/models"
        )
        #expect(
            try ProviderEndpoint.appending("v1/messages", to: "http://127.0.0.1:11434")
                .absoluteString == "http://127.0.0.1:11434/v1/messages"
        )
    }
}
