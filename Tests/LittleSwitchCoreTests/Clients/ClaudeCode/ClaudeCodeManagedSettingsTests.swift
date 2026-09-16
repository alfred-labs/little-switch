import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Claude Code managed settings")
struct ClaudeCodeManagedSettingsTests {
    @Test("Resolver uses a native default alias and gives eligible families their 1M reference")
    func extendedContextEnvironment() throws {
        let fixture = fixture()

        let managed = try ClaudeCodeManagedSettings.resolve(
            providers: [fixture.provider],
            mappings: fixture.mappings,
            configuration: ClaudeCodeConfiguration(
                defaultModel: "claude-sonnet-5",
                contextMode: .extended1M
            )
        )

        #expect(managed.model == "sonnet")
        #expect(managed.environment["ANTHROPIC_DEFAULT_FABLE_MODEL"] == "claude-fable-5-1")
        #expect(managed.environment["ANTHROPIC_DEFAULT_OPUS_MODEL"] == "claude-opus-5")
        #expect(managed.environment["ANTHROPIC_DEFAULT_SONNET_MODEL"] == "claude-sonnet-5[1m]")
        #expect(
            managed.environment["ANTHROPIC_DEFAULT_HAIKU_MODEL"]
                == "claude-haiku-4-5-20251001"
        )
    }

    @Test("Resolver emits the complete gateway environment")
    func completeEnvironment() throws {
        let fixture = fixture()

        let managed = try ClaudeCodeManagedSettings.resolve(
            providers: [fixture.provider],
            mappings: fixture.mappings,
            configuration: ClaudeCodeConfiguration(defaultModel: "claude-sonnet-5")
        )

        #expect(
            managed
                == ClaudeCodeManagedSettings(
                    model: "sonnet",
                    environment: [
                        "ANTHROPIC_DEFAULT_MODEL": "sonnet",
                        "ANTHROPIC_BASE_URL": "http://127.0.0.1:11436",
                        "ANTHROPIC_API_KEY": "",
                        "ANTHROPIC_AUTH_TOKEN": ProductIdentity.gatewayAPIKey,
                        "ANTHROPIC_DEFAULT_FABLE_MODEL": "claude-fable-5-1",
                        "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-5",
                        "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-5[1m]",
                        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5-20251001",
                        "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME": "Fable 5.1 ↦",
                        "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME": "Opus 5 ↦",
                        "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "Sonnet 5 ↦ (1M context)",
                        "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME": "Haiku 4.5 ↦",
                        "ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION": "Via LittleSwitch",
                        "ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION": "Via LittleSwitch",
                        "ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION": "Via LittleSwitch",
                        "ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION": "Via LittleSwitch",
                        "CLAUDE_CODE_USE_ANTHROPIC_AWS": "",
                        "CLAUDE_CODE_USE_BEDROCK": "",
                        "CLAUDE_CODE_USE_FOUNDRY": "",
                        "CLAUDE_CODE_USE_MANTLE": "",
                        "CLAUDE_CODE_USE_VERTEX": "",
                        "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
                        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "",
                        "ENABLE_TOOL_SEARCH": "true",
                        "CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": "4",
                        "CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY": "4",
                        "DISABLE_TELEMETRY": "1",
                        "DISABLE_ERROR_REPORTING": "1",
                        "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
                        "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
                    ]
                )
        )
    }

    @Test("The base URL follows the trust state of the loopback authority")
    func baseURLFollowsTrust() throws {
        let fixture = fixture()
        let configuration = ClaudeCodeConfiguration(defaultModel: "claude-sonnet-5")

        let untrusted = try ClaudeCodeManagedSettings.resolve(
            providers: [fixture.provider],
            mappings: fixture.mappings,
            configuration: configuration,
            tlsEnabled: false
        )
        let trusted = try ClaudeCodeManagedSettings.resolve(
            providers: [fixture.provider],
            mappings: fixture.mappings,
            configuration: configuration,
            tlsEnabled: true
        )

        #expect(
            untrusted.environment["ANTHROPIC_BASE_URL"]
                == ClaudeProfileIdentity.gatewayHTTPBaseURL
        )
        #expect(
            trusted.environment["ANTHROPIC_BASE_URL"]
                == ClaudeProfileIdentity.gatewayBaseURL
        )
    }

    @Test("Concurrency env stays fixed regardless of the mapped provider limits")
    func fixedConcurrency() throws {
        let fixture = fixture()
        var limited = fixture.provider
        limited.maximumParallelRequests = 2
        var generous = fixture.provider
        generous.maximumParallelRequests = 31
        let configuration = ClaudeCodeConfiguration(defaultModel: "claude-sonnet-5")

        let original = try ClaudeCodeManagedSettings.resolve(
            providers: [fixture.provider],
            mappings: fixture.mappings,
            configuration: configuration
        )
        let remappedLow = try ClaudeCodeManagedSettings.resolve(
            providers: [limited],
            mappings: fixture.mappings,
            configuration: configuration
        )
        let remappedHigh = try ClaudeCodeManagedSettings.resolve(
            providers: [generous],
            mappings: fixture.mappings,
            configuration: configuration
        )

        #expect(original.environment["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"] == "4")
        #expect(original.environment["CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY"] == "4")
        #expect(remappedLow == original)
        #expect(remappedHigh == original)
    }

    @Test("An unmapped preferred default is normalized before resolving aliases")
    func normalizesDefault() throws {
        let fixture = fixture()
        var mappings = fixture.mappings
        mappings.removeValue(forKey: "claude-opus-5")

        let managed = try ClaudeCodeManagedSettings.resolve(
            providers: [fixture.provider],
            mappings: mappings,
            configuration: ClaudeCodeConfiguration(defaultModel: "claude-opus-5")
        )

        #expect(managed.model == "sonnet")
        #expect(managed.environment["ANTHROPIC_DEFAULT_OPUS_MODEL"] == "claude-opus-5")
    }

    @Test("Changing physical capacity preserves the family and updates only its context presentation")
    func physicalTargetChangePreservesSignature() throws {
        let fixture = fixture()
        let configuration = ClaudeCodeConfiguration(defaultModel: "claude-sonnet-5")
        let original = try ClaudeCodeManagedSettings.resolve(
            providers: [fixture.provider],
            mappings: fixture.mappings,
            configuration: configuration
        )
        var replacementMappings = fixture.mappings
        replacementMappings["claude-sonnet-5"] = ModelMapping(
            providerID: fixture.provider.id,
            modelID: "sonnet"
        )

        let replacement = try ClaudeCodeManagedSettings.resolve(
            providers: [fixture.provider],
            mappings: replacementMappings,
            configuration: configuration
        )

        var expected = original
        expected.environment["ANTHROPIC_DEFAULT_SONNET_MODEL"] = "claude-sonnet-5"
        expected.environment["ANTHROPIC_DEFAULT_SONNET_MODEL_NAME"] = "Sonnet 5 ↦"
        #expect(replacement == expected)
    }

    @Test("Resolver rejects empty mappings for a valid catalog")
    func emptyMappings() {
        let fixture = fixture()

        #expect(throws: ClaudeCodeManagedSettings.Error.noMappedModel) {
            try ClaudeCodeManagedSettings.resolve(
                providers: [fixture.provider],
                mappings: [:],
                configuration: .disconnected
            )
        }
    }

    @Test("Tool search is always on and the kill switch is never shipped")
    func toolSearchEnvironmentInvariants() throws {
        let fixture = fixture()

        let environment = try ClaudeCodeManagedSettings.resolve(
            providers: [fixture.provider],
            mappings: fixture.mappings,
            configuration: ClaudeCodeConfiguration(defaultModel: "claude-sonnet-5")
        ).environment

        // Always on — activation is client-driven, not a little-switch toggle.
        #expect(environment["ENABLE_TOOL_SEARCH"] == "true")
        // The kill switch is never written: it disables all experimental
        // betas, including the [1m] feature, and silently forces standard
        // mode over ENABLE_TOOL_SEARCH (§4.1).
        #expect(environment["CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS"] == nil)
    }

    @Test("Relabeling a sparse legacy signature never invents family mappings")
    func sparsePresentationUpdate() {
        let legacy = ClaudeCodeManagedSettings(model: "claude-sonnet-5", environment: ["CUSTOM_SETTING": "keep"])
        #expect(legacy.withModelIndicator(.none) == legacy)
    }

    private func fixture() -> (provider: Provider, mappings: [String: ModelMapping]) {
        let providerID = UUID()
        let models = [
            DiscoveredModel(id: "glm-5.3-flash", contextWindowOverride: 1_000_000),
            DiscoveredModel(id: "opus"),
            DiscoveredModel(id: "sonnet"),
            DiscoveredModel(id: "haiku"),
        ]
        let provider = Provider(
            id: providerID,
            name: "z.ai",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: models,
            maximumParallelRequests: 7
        )
        return (
            provider,
            [
                "claude-opus-5": ModelMapping(providerID: providerID, modelID: "opus"),
                "claude-sonnet-5": ModelMapping(
                    providerID: providerID,
                    modelID: "glm-5.3-flash"
                ),
                "claude-haiku-4-5-20251001": ModelMapping(
                    providerID: providerID,
                    modelID: "haiku"
                ),
            ]
        )
    }
}
