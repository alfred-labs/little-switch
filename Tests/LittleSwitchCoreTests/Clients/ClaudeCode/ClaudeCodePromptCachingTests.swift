import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Claude Code prompt caching")
struct ClaudeCodePromptCachingTests {
    @Test(
        "Connecting leaves prompt caching enabled by default",
        arguments: [ClaudeCodeContextMode.standard, .extended1M], [false, true]
    )
    func freshProfile(contextMode: ClaudeCodeContextMode, tlsEnabled: Bool) throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        let managed = try resolvedSettings(contextMode: contextMode, tlsEnabled: tlsEnabled)

        try fixture.manager.activate(managed: managed)

        let environment = try environment(in: fixture)
        #expect(!environment.keys.contains { $0.hasPrefix("DISABLE_PROMPT_CACHING") })
        #expect(try fixture.manager.status(expected: managed) == .active)
        try fixture.manager.restore()
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.settings.path))
    }

    @Test(
        "An old cache override is retired while preserving the original preference",
        arguments: [nil, "0", "1"] as [String?]
    )
    func migratesLegacyOverride(originalValue: String?) throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        let managed = try resolvedSettings()
        var originalEnvironment = ["EDITOR": "vim"]
        originalEnvironment["DISABLE_PROMPT_CACHING"] = originalValue
        let original = try JSONSerialization.data(
            withJSONObject: ["theme": "dark", "env": originalEnvironment],
            options: [.sortedKeys]
        )
        try fixture.writeSettings(original, permissions: 0o640)
        var legacy = managed
        legacy.environment["DISABLE_PROMPT_CACHING"] = "1"
        try fixture.manager.activate(managed: legacy)
        let backup = try #require(fixture.backups().only)

        #expect(try fixture.manager.status(expected: managed) == .drifted)
        try fixture.manager.activate(managed: managed)
        try fixture.manager.activate(managed: managed)

        let environment = try environment(in: fixture)
        #expect(environment["DISABLE_PROMPT_CACHING"] as? String == originalValue)
        #expect(environment["EDITOR"] as? String == "vim")
        #expect(try fixture.backups() == [backup])
        #expect(try fixture.manager.status(expected: managed) == .active)
        try fixture.manager.restore()
        #expect(try Data(contentsOf: fixture.paths.settings) == original)
        #expect(try permissions(of: fixture.paths.settings) == 0o640)
    }

    @Test(
        "Migration keeps caching enabled when the user already removed or cleared the old override",
        arguments: [nil, "0"] as [String?]
    )
    func preservesExternalCorrection(correctedValue: String?) throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        let managed = try resolvedSettings()
        var legacy = managed
        legacy.environment["DISABLE_PROMPT_CACHING"] = "1"
        try fixture.manager.activate(managed: legacy)
        var current = try jsonObject(Data(contentsOf: fixture.paths.settings))
        var correctedEnvironment = try #require(current["env"] as? [String: Any])
        correctedEnvironment["DISABLE_PROMPT_CACHING"] = correctedValue
        current["env"] = correctedEnvironment
        try JSONSerialization.data(withJSONObject: current).write(to: fixture.paths.settings)

        try fixture.manager.activate(managed: managed)

        #expect(try environment(in: fixture)["DISABLE_PROMPT_CACHING"] as? String == correctedValue)
        try fixture.manager.restore()
        if let correctedValue {
            let restored = try jsonObject(Data(contentsOf: fixture.paths.settings))
            let expected: [String: Any] = ["env": ["DISABLE_PROMPT_CACHING": correctedValue]]
            #expect(NSDictionary(dictionary: restored).isEqual(to: expected))
        } else {
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.settings.path))
        }
    }

    private func environment(in fixture: ClaudeCodeProfileFixture) throws -> [String: Any] {
        try #require(
            jsonObject(Data(contentsOf: fixture.paths.settings))["env"] as? [String: Any]
        )
    }

    private func resolvedSettings(
        contextMode: ClaudeCodeContextMode = .standard,
        tlsEnabled: Bool = false
    ) throws -> ClaudeCodeManagedSettings {
        let providerID = UUID()
        let model = DiscoveredModel(id: "test-model", contextWindowOverride: 1_000_000)
        let provider = Provider(
            id: providerID,
            name: "Test provider",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [model]
        )
        return try ClaudeCodeManagedSettings.resolve(
            providers: [provider],
            mappings: [
                "claude-sonnet-5": ModelMapping(providerID: providerID, modelID: model.id)
            ],
            configuration: ClaudeCodeConfiguration(
                defaultModel: "claude-sonnet-5",
                contextMode: contextMode
            ),
            tlsEnabled: tlsEnabled
        )
    }
}
