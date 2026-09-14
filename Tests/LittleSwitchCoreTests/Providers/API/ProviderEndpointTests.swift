import Foundation
import LittleSwitchCommon
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

    @Test("The hosted OpenAI preset endpoints avoid a duplicated /v1 segment")
    func openAIEndpoints() throws {
        let provider = Provider(
            name: "OpenAI",
            baseURL: "https://api.openai.com",
            authMode: .bearer
        )

        #expect(
            try ProviderEndpoint.forwarding(.responses, for: provider).absoluteString
                == "https://api.openai.com/v1/responses"
        )
        #expect(
            try ProviderEndpoint.forwarding(.chatCompletions, for: provider).absoluteString
                == "https://api.openai.com/v1/chat/completions"
        )
        #expect(
            try ProviderRequestBuilder.discovery(provider: provider, secret: nil).url
                == "https://api.openai.com/v1/models"
        )
    }
}
