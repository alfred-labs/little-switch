import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Provider request construction")
struct ProviderRequestBuilderTests {
    @Test("API-key and unauthenticated providers use distinct headers")
    func authenticationModes() throws {
        let apiKey = Provider(name: "A", baseURL: "https://example.com", authMode: .xAPIKey)
        let none = Provider(name: "B", baseURL: "http://127.0.0.1:11434", authMode: .none)
        let apiRequest = try ProviderRequestBuilder.discovery(provider: apiKey, secret: "secret")
        let noneRequest = try ProviderRequestBuilder.discovery(provider: none, secret: nil)
        #expect(apiRequest.headers["x-api-key"] == ["secret"])
        #expect(apiRequest.headers["authorization"].isEmpty)
        #expect(noneRequest.headers["x-api-key"].isEmpty)
        #expect(noneRequest.headers["authorization"].isEmpty)
        let anonymousDiscovery = try ProviderRequestBuilder.discovery(
            provider: apiKey,
            secret: nil
        )
        #expect(anonymousDiscovery.headers["x-api-key"].isEmpty)
        #expect(anonymousDiscovery.headers["authorization"].isEmpty)
        let bearer = Provider(
            name: "C",
            baseURL: "https://example.com",
            authMode: .bearer
        )
        let anonymousMessage = try ProviderRequestBuilder.message(
            provider: bearer,
            secret: nil,
            headers: [:],
            body: Data()
        )
        #expect(anonymousMessage.headers["authorization"].isEmpty)
    }

    @Test("Message requests strip ambient credentials and preserve safe headers")
    func messageHeaders() throws {
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:8000/api",
            authMode: .bearer
        )
        var incoming: HTTPHeaders = [
            "authorization": "incoming",
            "cookie": "private",
            "proxy-authorization": "proxy",
            "x-api-key": "incoming-key",
            "host": "localhost:11436",
            "anthropic-beta": "tools-2025",
            "content-type": "application/json",
            "connection": "x-private-hop",
            "x-private-hop": "private",
            "x-oai-attestation": "openai-proof",
            "x-codex-turn-metadata": "turn-blob",
        ]
        incoming.add(name: "x-request-id", value: "abc")
        let request = try ProviderRequestBuilder.message(
            provider: provider,
            secret: "selected",
            headers: incoming,
            body: Data("{}".utf8)
        )
        #expect(request.url == "http://127.0.0.1:8000/api/v1/messages")
        #expect(request.method == .POST)
        #expect(request.headers["authorization"] == ["Bearer selected"])
        #expect(request.headers["cookie"].isEmpty)
        #expect(request.headers["proxy-authorization"].isEmpty)
        #expect(request.headers["x-api-key"].isEmpty)
        #expect(request.headers["host"].isEmpty)
        #expect(request.headers["connection"].isEmpty)
        #expect(request.headers["x-private-hop"].isEmpty)
        #expect(request.headers["x-oai-attestation"].isEmpty)
        #expect(request.headers["x-codex-turn-metadata"].isEmpty)
        #expect(request.headers["anthropic-beta"] == ["tools-2025"])
        #expect(request.headers["x-request-id"] == ["abc"])
    }

    @Test("Only allowlisted headers survive forwarding; unknown headers are dropped")
    func allowlistHeaders() throws {
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:8000/api",
            authMode: .bearer
        )
        let request = try ProviderRequestBuilder.message(
            provider: provider,
            secret: "selected",
            headers: [
                "content-type": "application/json",
                "anthropic-beta": "tools-2025",
                "anthropic-version": "2023-06-01",
                "accept": "application/json",
                "user-agent": "LittleSwitch/1.0",
                "x-request-id": "abc",
                "x-future-provider-token": "leak",
                "x-custom-session": "private",
                "openai-organization": "org-123",
            ],
            body: Data("{}".utf8)
        )
        #expect(request.headers["content-type"] == ["application/json"])
        #expect(request.headers["anthropic-beta"] == ["tools-2025"])
        #expect(request.headers["anthropic-version"] == ["2023-06-01"])
        #expect(request.headers["accept"] == ["application/json"])
        #expect(request.headers["user-agent"] == ["LittleSwitch/1.0"])
        #expect(request.headers["x-request-id"] == ["abc"])
        // Unknown headers are dropped by the allowlist, not forwarded.
        #expect(request.headers["x-future-provider-token"].isEmpty)
        #expect(request.headers["x-custom-session"].isEmpty)
        #expect(request.headers["openai-organization"].isEmpty)
    }

    @Test("Responses requests use the OpenAI endpoint and remove client compression metadata")
    func responsesRequest() throws {
        let provider = Provider(
            name: "vLLM",
            baseURL: "http://127.0.0.1:8000/api",
            authMode: .bearer
        )
        let request = try ProviderRequestBuilder.responses(
            provider: provider,
            secret: "selected",
            headers: [
                "authorization": "incoming",
                "content-encoding": "zstd",
                "content-length": "42",
                "content-type": "application/json",
            ],
            body: Data(#"{"model":"upstream"}"#.utf8)
        )

        #expect(request.url == "http://127.0.0.1:8000/api/v1/responses")
        #expect(request.method == .POST)
        #expect(request.headers["authorization"] == ["Bearer selected"])
        #expect(request.headers["content-encoding"].isEmpty)
        #expect(request.headers["content-length"].isEmpty)
        #expect(request.headers["content-type"] == ["application/json"])
    }

    @Test("z.ai Chat Completions requests use the Coding endpoint")
    func zaiChatCompletionsRequest() throws {
        let provider = Provider(
            name: "z.ai",
            baseURL: ProviderPreset.zai.baseURL,
            authMode: .bearer,
            anthropicBaseURL: ProviderPreset.zai.anthropicBaseURL
        )
        let request = try ProviderRequestBuilder.chatCompletions(
            provider: provider,
            secret: "selected",
            headers: ["content-type": "application/json"],
            body: Data(#"{"model":"glm-5.3-flash"}"#.utf8)
        )

        #expect(request.url == "https://api.z.ai/api/coding/paas/v4/chat/completions")
        #expect(request.headers["authorization"] == ["Bearer selected"])
    }

    @Test("Generic Chat Completions requests stay on the provider base URL")
    func genericChatCompletionsRequest() throws {
        let provider = Provider(
            name: "OpenAI compatible",
            baseURL: "https://example.com/api",
            authMode: .bearer
        )
        let request = try ProviderRequestBuilder.chatCompletions(
            provider: provider,
            secret: nil,
            headers: [:],
            body: Data(#"{"model":"custom"}"#.utf8)
        )

        #expect(request.url == "https://example.com/api/v1/chat/completions")
    }
}
