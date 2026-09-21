import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Codex model catalog")
struct CodexCatalogTests {
    @Test("Slugs are the readable provider and model pair")
    func stableSlugs() throws {
        let providerID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let mapping = ModelMapping(providerID: providerID, modelID: "qwen/coder:latest")
        let provider = Provider(
            id: providerID,
            name: "Renamed",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: mapping.modelID)]
        )

        #expect(CodexCatalog.slug(for: mapping, in: [provider]) == "renamed/qwen/coder:latest")

        let catalog = try CodexCatalog.make(
            providers: [provider],
            configuration: CodexConfiguration(defaultModel: mapping)
        )
        #expect(
            catalog.models.first?.slug
                == CodexCatalog.slug(for: mapping, in: [provider])
        )
    }

    @Test("Catalog puts the default first and encodes complete Codex metadata")
    func catalogMetadata() throws {
        let localID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let remoteID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let localDefault = ModelMapping(providerID: localID, modelID: "zeta")
        let providers = [
            Provider(
                id: remoteID,
                name: "Remote",
                baseURL: "https://example.com",
                authMode: .bearer,
                models: [
                    DiscoveredModel(
                        id: "alpha",
                        detectedContextWindow: 262_144,
                        contextWindowOverride: 400_000
                    )
                ]
            ),
            Provider(
                id: localID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                models: [DiscoveredModel(id: "beta"), DiscoveredModel(id: "zeta")]
            ),
        ]

        let catalog = try CodexCatalog.make(
            providers: providers,
            configuration: CodexConfiguration(
                defaultModel: localDefault,
                excludedModels: [ModelMapping(providerID: localID, modelID: "beta")]
            )
        )

        #expect(catalog.models.map(\.displayName) == ["Local/zeta", "Remote/alpha", "little-switch-auto-review"])
        #expect(catalog.models.map(\.priority) == [0, 1, 2])
        #expect(catalog.models.map(\.contextWindow) == [128_000, 262_144, 128_000])
        let first = try #require(catalog.models.first)
        #expect(first.description == "LittleSwitch")
        #expect(first.defaultReasoningLevel == "medium")
        #expect(first.supportedReasoningLevels == CodexCatalog.supportedReasoningLevels)
        #expect(first.shellType == "default")
        #expect(first.visibility == "list")
        #expect(first.supportedInAPI)
        #expect(first.additionalSpeedTiers.isEmpty)
        #expect(first.availabilityNUX == nil)
        #expect(first.upgrade == nil)
        #expect(first.baseInstructions == CodexCatalog.baseInstructions)
        #expect(first.modelMessages == nil)
        #expect(!first.supportsReasoningSummaries)
        #expect(first.defaultReasoningSummary == "auto")
        #expect(!first.supportVerbosity)
        #expect(first.defaultVerbosity == nil)
        #expect(first.applyPatchToolType == nil)
        #expect(first.webSearchToolType == "text")
        #expect(first.truncationPolicy == CodexTruncationPolicy(mode: "bytes", limit: 10_000))
        #expect(first.supportsParallelToolCalls)
        #expect(!first.supportsImageDetailOriginal)
        #expect(first.maxContextWindow == first.contextWindow)
        #expect(first.autoCompactTokenLimit == nil)
        #expect(first.effectiveContextWindowPercent == 95)
        #expect(first.experimentalSupportedTools.isEmpty)
        #expect(first.inputModalities == ["text", "image"])
        #expect(!first.supportsSearchTool)
        #expect(first.multiAgentVersion == "v2")
    }

    @Test("A mixed OpenAI and local catalog keeps both families exposed")
    func mixedProviderCohabitation() throws {
        let openAIID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let localID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let providers = [
            Provider(
                id: openAIID,
                name: "OpenAI",
                baseURL: "https://api.openai.com",
                authMode: .bearer,
                models: [
                    DiscoveredModel(id: "gpt-5.5"),
                    DiscoveredModel(id: "gpt-5.4-mini"),
                ]
            ),
            Provider(
                id: localID,
                name: "z.ai",
                baseURL: "https://api.z.ai/api/coding/paas/v4",
                authMode: .bearer,
                models: [DiscoveredModel(id: "glm-5.3")]
            ),
        ]
        let configuration = CodexConfiguration(
            defaultModel: ModelMapping(providerID: openAIID, modelID: "gpt-5.5"),
            excludedModels: [ModelMapping(providerID: openAIID, modelID: "gpt-5.4-mini")]
        )

        let catalog = try CodexCatalog.make(
            providers: providers,
            configuration: configuration
        )

        let exposed = catalog.models.filter { $0.slug != CodexCatalog.managedAutoReviewModel }
        #expect(exposed.map(\.slug) == ["openai/gpt-5.5", "z.ai/glm-5.3"])
        #expect(exposed.map(\.displayName) == ["OpenAI/gpt-5.5", "z.ai/glm-5.3"])
        #expect(
            Set(exposed.map { $0.slug.lowercased() }).count == exposed.count,
            "slugs stay unique case-insensitively across provider families"
        )
        #expect(catalog.models.last?.slug == CodexCatalog.managedAutoReviewModel)
        #expect(catalog.models.last?.description == "Approval reviews via OpenAI/gpt-5.5")
    }

    @Test("Image modalities follow provider overrides and detected capabilities")
    func imageModalitiesResolution() throws {
        let providerID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))

        func modalities(
            override: ProviderImageInputOverride?,
            detected: Bool?
        ) throws -> [String] {
            var provider = Provider(
                id: providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                models: [DiscoveredModel(id: "qwen", supportsImageInput: detected)]
            )
            provider.imageInputOverride = override
            let catalog = try CodexCatalog.make(
                providers: [provider],
                configuration: CodexConfiguration()
            )
            return try #require(catalog.models.first?.inputModalities)
        }

        #expect(try modalities(override: nil, detected: nil) == ["text", "image"])
        #expect(try modalities(override: nil, detected: true) == ["text", "image"])
        #expect(try modalities(override: nil, detected: false) == ["text"])
        #expect(try modalities(override: .enabled, detected: false) == ["text", "image"])
        #expect(try modalities(override: .disabled, detected: true) == ["text"])
    }

    @Test("Encoded catalog advertises every Codex reasoning effort")
    func encodedReasoningEfforts() throws {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "qwen")]
        )
        let data = try CodexCatalog.encode(
            providers: [provider],
            configuration: CodexConfiguration()
        )
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let models = try #require(root["models"] as? [[String: Any]])
        let model = try #require(models.first)

        #expect(model["default_reasoning_level"] as? String == "medium")
        #expect(model["multi_agent_version"] as? String == "v2")
        let levels = try #require(
            model["supported_reasoning_levels"] as? [[String: String]]
        )
        #expect(
            levels.map { $0["effort"] }
                == ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
        )
        #expect(levels.allSatisfy { $0["description"]?.isEmpty == false })

        for key in [
            "availability_nux",
            "upgrade",
            "model_messages",
            "default_verbosity",
            "apply_patch_tool_type",
            "auto_compact_token_limit",
        ] {
            #expect(model[key] is NSNull)
        }
        #expect(data.last == UInt8(ascii: "\n"))
    }

    @Test("An empty exposed catalog is rejected")
    func rejectsEmptyCatalog() {
        #expect(throws: CodexCatalog.Error.empty) {
            try CodexCatalog.make(providers: [], configuration: .disconnected)
        }
    }

    @Test("An unparseable managed catalog is rejected before native merging")
    func rejectsUnparseableManagedCatalog() {
        #expect(throws: CodexCatalog.Error.empty) {
            try CodexCatalog.mergedData(managedData: Data("not-json".utf8), nativeCatalogData: nil)
        }
    }

    @Test("Optional catalog token limits encode as numbers when present")
    func optionalTokenEncoding() throws {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "qwen")]
        )
        var model = try #require(
            CodexCatalog.make(
                providers: [provider],
                configuration: .disconnected
            ).models.first
        )
        model.autoCompactTokenLimit = 64_000

        let data = try JSONEncoder().encode(CodexModelCatalog(models: [model]))
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let models = try #require(root["models"] as? [[String: Any]])

        #expect(models.first?["auto_compact_token_limit"] as? Int == 64_000)
    }
}
