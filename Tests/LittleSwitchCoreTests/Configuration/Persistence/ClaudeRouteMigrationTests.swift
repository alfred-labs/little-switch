import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Claude route configuration migration")
struct ClaudeRouteMigrationTests {
    @Test("Fable upgrades preserve the provider mapping and the selected context", arguments: 1...8)
    func migratesFable(storedVersion: Int) throws {
        let provider = Provider(
            name: "Gateway",
            baseURL: "https://example.com",
            authMode: .bearer,
            models: [DiscoveredModel(id: "large", detectedContextWindow: 1_048_576)]
        )
        let mapping = ModelMapping(providerID: provider.id, modelID: "large")
        let original = AppConfiguration(
            version: storedVersion,
            providers: [provider],
            mappings: ["claude-fable-5": mapping, "claude-sonnet-5": mapping],
            connected: true,
            claudeCode: ClaudeCodeConfiguration(
                connected: true, defaultModel: "claude-fable-5", contextMode: .extended1M)
        )
        let migrated = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(original))
        var expected = original
        expected.version = 9
        expected.mappings = ["claude-fable-5-1": mapping, "claude-sonnet-5": mapping]
        expected.claudeCode.defaultModel = "claude-fable-5-1"
        #expect(migrated == expected)
        let managed = try ClaudeCodeManagedSettings.resolve(
            providers: migrated.providers, mappings: migrated.mappings, configuration: migrated.claudeCode)
        #expect(managed.model == "claude-fable-5-1[1m]")
        #expect(managed.environment["ANTHROPIC_DEFAULT_FABLE_MODEL"] == "claude-fable-5-1")
    }

    @Test("An explicit Fable 5.1 mapping takes precedence over a legacy mapping")
    func preservesCurrentMapping() throws {
        let legacy = ModelMapping(providerID: UUID(), modelID: "old")
        let current = ModelMapping(providerID: UUID(), modelID: "new")
        let original = AppConfiguration(
            version: 8,
            mappings: ["claude-fable-5": legacy, "claude-fable-5-1": current, "unknown": legacy],
            claudeCode: ClaudeCodeConfiguration(defaultModel: "claude-fable-5-1")
        )
        let migrated = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(original))
        #expect(migrated.mappings == ["claude-fable-5-1": current])
        #expect(migrated.claudeCode.defaultModel == "claude-fable-5-1")
    }
}
