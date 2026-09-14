import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Provider authentication headers")
struct ProviderAuthenticationTests {
    @Test("A credential is sent in the header its mode names, and omitted when empty")
    func credentialHeaders() throws {
        let bearer = Provider(
            name: "OpenAI Compatible",
            baseURL: "http://127.0.0.1:8000",
            authMode: .bearer
        )
        let apiKey = Provider(
            name: "Keyed",
            baseURL: "https://example.com",
            authMode: .xAPIKey
        )
        let anonymous = Provider(
            name: "Ollama",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none
        )
        let scripted = Provider(
            name: "Vault",
            baseURL: "https://vault.example.com",
            authMode: .bearer,
            credentialSource: .script
        )

        #expect(
            try ProviderRequestBuilder.discovery(provider: bearer, secret: nil)
                .headers["authorization"].isEmpty
        )
        #expect(
            try ProviderRequestBuilder.discovery(provider: bearer, secret: "  ")
                .headers["authorization"] == ["Bearer   "]
        )
        #expect(
            try ProviderRequestBuilder.discovery(provider: bearer, secret: "secret")
                .headers["authorization"] == ["Bearer secret"]
        )
        #expect(
            try ProviderRequestBuilder.discovery(provider: apiKey, secret: "secret")
                .headers["x-api-key"] == ["secret"]
        )
        #expect(
            try ProviderRequestBuilder.discovery(provider: apiKey, secret: nil)
                .headers["x-api-key"].isEmpty
        )
        #expect(
            try ProviderRequestBuilder.discovery(provider: anonymous, secret: "ignored")
                .headers["authorization"].isEmpty
        )
        #expect(
            try ProviderRequestBuilder.discovery(provider: scripted, secret: "script-token")
                .headers["authorization"] == ["Bearer script-token"]
        )
        #expect(
            try ProviderRequestBuilder.discovery(provider: scripted, secret: nil)
                .headers["authorization"].isEmpty
        )
    }

    @Test("A configuration written before the modes merged still decodes")
    func legacyOptionalBearerDecodes() throws {
        let decoder = JSONDecoder()

        #expect(try decoder.decode(AuthMode.self, from: Data("\"optional-bearer\"".utf8)) == .bearer)
        #expect(try decoder.decode(AuthMode.self, from: Data("\"bearer\"".utf8)) == .bearer)
        #expect(try decoder.decode(AuthMode.self, from: Data("\"x-api-key\"".utf8)) == .xAPIKey)
        #expect(try decoder.decode(AuthMode.self, from: Data("\"none\"".utf8)) == AuthMode.none)
        // The old script mode moved to CredentialSource; the header type no
        // longer carries it, and stored configurations are mapped at decode.
        #expect(throws: DecodingError.self) {
            try decoder.decode(AuthMode.self, from: Data("\"script\"".utf8))
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(AuthMode.self, from: Data("\"kerberos\"".utf8))
        }
    }
}
