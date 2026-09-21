import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenCode managed settings")
struct OpenCodeManagedSettingsTests {
    private struct Fixture {
        var providers: [Provider]
        var alpha: ModelMapping
        var hidden: ModelMapping
        var beta: ModelMapping
        var codex: CodexConfiguration
    }

    @Test("Resolved profiles always connect the exact LittleSwitch MCP search server over HTTPS")
    func resolvedMCPServer() throws {
        let fixture = try fixture()
        let managed = try OpenCodeManagedSettings.resolve(
            providers: fixture.providers,
            codex: fixture.codex,
            configuration: .disconnected
        )
        let data = try OpenCodeSettingsDocument.activating(nil, managed: managed)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expected: [String: Any] = [
            "web": [
                "type": "remote",
                "url": "https://127.0.0.1:11436/api/mcp",
                "enabled": true,
                "oauth": false,
                "timeout": 150_000,
            ]
        ]

        #expect((root["mcp"] as? NSDictionary) == expected as NSDictionary)
        #expect(Set(root.keys) == ["model", "provider", "mcp"])
    }

    @Test("Resolution emits the exact HTTPS provider and an independent default")
    func resolvedProvider() throws {
        let fixture = try fixture()
        let managed = try OpenCodeManagedSettings.resolve(
            providers: fixture.providers,
            codex: fixture.codex,
            configuration: OpenCodeConfiguration(defaultModel: fixture.alpha)
        )
        let alphaSlug = CodexCatalog.slug(for: fixture.alpha, in: fixture.providers)
        let betaSlug = CodexCatalog.slug(for: fixture.beta, in: fixture.providers)

        #expect(
            managed
                == OpenCodeManagedSettings(
                    model: "little-switch/\(alphaSlug)",
                    provider: OpenCodeManagedProvider(
                        npm: "@ai-sdk/openai",
                        name: "LittleSwitch",
                        options: OpenCodeManagedProviderOptions(
                            baseURL: "https://127.0.0.1:11436/v1",
                            apiKey: ProductIdentity.gatewayAPIKey
                        ),
                        models: [
                            alphaSlug: OpenCodeManagedModel(
                                name: "Alpha/a",
                                limit: OpenCodeManagedModelLimit(context: 128_000, output: 8_192),
                                modalities: OpenCodeManagedModelModalities(input: ["text", "image"], output: ["text"])
                            ),
                            betaSlug: OpenCodeManagedModel(
                                name: "Beta/b",
                                limit: OpenCodeManagedModelLimit(output: 4_096),
                                modalities: OpenCodeManagedModelModalities(input: ["text", "image"], output: ["text"])
                            ),
                        ]
                    ),
                    mcp: .littleSwitch
                )
        )
    }

    @Test("Only Codex-exposed models are emitted")
    func onlyExposedModels() throws {
        let fixture = try fixture()
        let managed = try OpenCodeManagedSettings.resolve(
            providers: fixture.providers,
            codex: fixture.codex,
            configuration: .disconnected
        )

        #expect(
            Set(managed.provider.models.keys)
                == [
                    CodexCatalog.slug(for: fixture.alpha, in: fixture.providers),
                    CodexCatalog.slug(for: fixture.beta, in: fixture.providers),
                ]
        )
        #expect(managed.model == "little-switch/\(CodexCatalog.slug(for: fixture.beta, in: fixture.providers))")
    }

    @Test("Limits require a known positive output budget")
    func limitPolicy() throws {
        let providerID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let models = [
            DiscoveredModel(id: "context-only", detectedContextWindow: 100_000),
            DiscoveredModel(id: "unknown"),
            DiscoveredModel(id: "zero-output", maxTokens: 0, detectedContextWindow: 50_000),
        ]
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:9000",
            authMode: .none,
            models: models
        )

        let managed = try OpenCodeManagedSettings.resolve(
            providers: [provider],
            codex: .disconnected,
            configuration: .disconnected
        )

        for model in models {
            let mapping = ModelMapping(providerID: providerID, modelID: model.id)
            #expect(managed.provider.models[CodexCatalog.slug(for: mapping, in: [provider])]?.limit == nil)
        }
    }

    @Test("A nonpositive context is omitted from an otherwise known limit")
    func nonpositiveContext() throws {
        let providerID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let mapping = ModelMapping(providerID: providerID, modelID: "negative-context")
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:9000",
            authMode: .none,
            models: [
                DiscoveredModel(
                    id: mapping.modelID,
                    maxTokens: 2_048,
                    detectedContextWindow: -1
                )
            ]
        )

        let managed = try OpenCodeManagedSettings.resolve(
            providers: [provider],
            codex: .disconnected,
            configuration: .disconnected
        )

        #expect(
            managed.provider.models[CodexCatalog.slug(for: mapping, in: [provider])]?.limit
                == OpenCodeManagedModelLimit(output: 2_048)
        )
    }

    @Test("No exposed model is rejected")
    func noExposedModel() throws {
        let fixture = try fixture()
        let codex = CodexConfiguration(
            excludedModels: [fixture.alpha, fixture.hidden, fixture.beta]
        )

        #expect(throws: OpenCodeManagedSettings.Error.noExposedModel) {
            try OpenCodeManagedSettings.resolve(
                providers: fixture.providers,
                codex: codex,
                configuration: .disconnected
            )
        }
    }

    @Test("Encoded settings contain no invented OpenCode capabilities")
    func encodedProviderSurface() throws {
        let fixture = try fixture()
        let managed = try OpenCodeManagedSettings.resolve(
            providers: fixture.providers,
            codex: fixture.codex,
            configuration: .disconnected
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(managed)) as? [String: Any]
        )
        let provider = try #require(object["provider"] as? [String: Any])
        let options = try #require(provider["options"] as? [String: Any])
        let encoded = try #require(String(data: JSONEncoder().encode(managed), encoding: .utf8))

        #expect(options["apiKey"] as? String == ProductIdentity.gatewayAPIKey)
        #expect(Set(options.keys) == ["apiKey", "baseURL"])
        #expect(Set(provider.keys) == ["models", "name", "npm", "options"])
        #expect(!encoded.contains("reason"))
        #expect(!encoded.contains("variant"))
        #expect(!encoded.localizedCaseInsensitiveContains("secret"))
        #expect(!encoded.localizedCaseInsensitiveContains("bearer"))
    }

    private func fixture() throws -> Fixture {
        let alphaID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let betaID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let alpha = ModelMapping(providerID: alphaID, modelID: "a")
        let hidden = ModelMapping(providerID: alphaID, modelID: "hidden")
        let beta = ModelMapping(providerID: betaID, modelID: "b")
        let providers = [
            Provider(
                id: alphaID,
                name: "Alpha",
                baseURL: "https://alpha.example.com",
                authMode: .none,
                models: [
                    DiscoveredModel(
                        id: "a",
                        maxTokens: 8_192,
                        detectedContextWindow: 128_000,
                        contextWindowOverride: 200_000
                    ),
                    DiscoveredModel(id: "hidden", maxTokens: 1_024),
                ]
            ),
            Provider(
                id: betaID,
                name: "Beta",
                baseURL: "https://beta.example.com",
                authMode: .none,
                models: [DiscoveredModel(id: "b", maxTokens: 4_096)]
            ),
        ]
        let codex = CodexConfiguration(defaultModel: beta, excludedModels: [hidden])
        return Fixture(
            providers: providers,
            alpha: alpha,
            hidden: hidden,
            beta: beta,
            codex: codex
        )
    }
}
