import Foundation
import Testing

@testable import LittleSwitchCommon

@Suite("Codex configuration")
struct CodexConfigurationTests {
    @Test("Model target identity is the stable provider and model mapping key")
    func modelTargetID() throws {
        let providerID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let target = CodexModelTarget(
            provider: Provider(
                id: providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none
            ),
            model: DiscoveredModel(id: "qwen")
        )

        #expect(target.id == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee|qwen")
    }

    @Test("All discovered models are exposed by default in stable display order")
    func defaultExposure() throws {
        let firstID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let secondID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let providers = [
            Provider(
                id: firstID,
                name: "z.ai",
                baseURL: "https://api.z.ai/api/anthropic",
                authMode: .bearer,
                models: [DiscoveredModel(id: "glm")]
            ),
            Provider(
                id: secondID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                models: [DiscoveredModel(id: "qwen:latest"), DiscoveredModel(id: "coder")]
            ),
        ]

        let targets = CodexConfiguration.disconnected.exposedModels(in: providers)

        #expect(targets.map(\.displayName) == ["Local/coder", "Local/qwen:latest", "z.ai/glm"])
        #expect(
            targets.map(\.mapping) == [
                ModelMapping(providerID: secondID, modelID: "coder"),
                ModelMapping(providerID: secondID, modelID: "qwen:latest"),
                ModelMapping(providerID: firstID, modelID: "glm"),
            ])
    }

    @Test("Exclusions disable individual models and new models remain exposed")
    func exclusions() {
        let providerID = UUID()
        let hidden = ModelMapping(providerID: providerID, modelID: "hidden")
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [
                DiscoveredModel(id: "hidden"),
                DiscoveredModel(id: "new"),
            ]
        )
        let configuration = CodexConfiguration(excludedModels: [hidden])

        #expect(
            configuration.exposedModels(in: [provider]).map(\.mapping) == [
                ModelMapping(providerID: providerID, modelID: "new")
            ])
    }

    @Test("The default falls back to the first exposed model")
    func defaultFallback() {
        let providerID = UUID()
        let first = ModelMapping(providerID: providerID, modelID: "alpha")
        let second = ModelMapping(providerID: providerID, modelID: "beta")
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "beta"), DiscoveredModel(id: "alpha")]
        )

        #expect(CodexConfiguration().resolvedDefaultModel(in: [provider]) == first)
        #expect(
            CodexConfiguration(defaultModel: second)
                .resolvedDefaultModel(in: [provider]) == second
        )
        #expect(
            CodexConfiguration(
                defaultModel: second,
                excludedModels: [second]
            ).resolvedDefaultModel(in: [provider]) == first
        )
        #expect(
            CodexConfiguration(
                defaultModel: ModelMapping(providerID: providerID, modelID: "missing")
            ).resolvedDefaultModel(in: [provider]) == first
        )
    }

    @Test("No default resolves when every model is excluded")
    func noDefault() {
        let providerID = UUID()
        let mapping = ModelMapping(providerID: providerID, modelID: "only")
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "only")]
        )

        #expect(
            CodexConfiguration(defaultModel: mapping, excludedModels: [mapping])
                .resolvedDefaultModel(in: [provider]) == nil
        )
    }

    @Test("Normalization deduplicates exclusions and resolves the default")
    func normalization() {
        let providerID = UUID()
        let hidden = ModelMapping(providerID: providerID, modelID: "hidden")
        let visible = ModelMapping(providerID: providerID, modelID: "visible")
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "visible"), DiscoveredModel(id: "hidden")]
        )
        let configuration = CodexConfiguration(
            connected: true,
            defaultModel: hidden,
            excludedModels: [hidden, hidden]
        )

        #expect(
            configuration.normalized(for: [provider])
                == CodexConfiguration(
                    connected: true,
                    defaultModel: visible,
                    excludedModels: [hidden]
                )
        )
    }

    @Test("Equal display names use mapping identity as a stable tie-breaker")
    func stableTieBreakers() throws {
        let firstID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let secondID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let providers = [(secondID, "same"), (firstID, "Same")].map { providerID, name in
            Provider(
                id: providerID,
                name: name,
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                models: [DiscoveredModel(id: "model")]
            )
        }
        let firstMapping = ModelMapping(providerID: firstID, modelID: "model")
        let secondMapping = ModelMapping(providerID: secondID, modelID: "model")

        #expect(
            CodexConfiguration.disconnected.availableModels(in: providers).map(\.mapping)
                == [firstMapping, secondMapping]
        )
        #expect(
            CodexConfiguration(excludedModels: [secondMapping, firstMapping])
                .normalized(for: providers).excludedModels
                == [firstMapping, secondMapping]
        )
    }
}
