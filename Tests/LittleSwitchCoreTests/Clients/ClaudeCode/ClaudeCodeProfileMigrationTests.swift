import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Claude Code profile migration")
struct ClaudeCodeProfileMigrationTests {
    @Test("Reactivation removes retired values still owned by LittleSwitch")
    func reactivationRetiresOwnedValues() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        let original = Data(#"{"theme":"dark"}"#.utf8)
        try fixture.writeSettings(original, permissions: 0o644)
        var legacyEnvironment = fixture.managed.environment
        legacyEnvironment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "true"
        legacyEnvironment["CLAUDE_CODE_DISABLE_TELEMETRY"] = "true"
        let legacy = ClaudeCodeManagedSettings(
            model: fixture.managed.model,
            environment: legacyEnvironment
        )
        var supportedEnvironment = fixture.managed.environment
        supportedEnvironment["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] = "1"
        supportedEnvironment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = ""
        supportedEnvironment["DISABLE_TELEMETRY"] = "1"
        let supported = ClaudeCodeManagedSettings(
            model: fixture.managed.model,
            environment: supportedEnvironment
        )

        try fixture.manager.activate(managed: legacy)
        let firstBackup = try #require(fixture.backups().only)
        try fixture.manager.activate(managed: supported)

        let root = try jsonObject(Data(contentsOf: fixture.paths.settings))
        let environment = try #require(root["env"] as? [String: Any])
        let nonessentialTraffic = try #require(
            environment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] as? String
        )
        #expect(nonessentialTraffic.isEmpty)
        #expect(environment["CLAUDE_CODE_DISABLE_TELEMETRY"] == nil)
        #expect(environment["DISABLE_TELEMETRY"] as? String == "1")
        #expect(environment["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] as? String == "1")
        #expect(try fixture.backups() == [firstBackup])
        try fixture.manager.restore()
        #expect(try Data(contentsOf: fixture.paths.settings) == original)
        #expect(try permissions(of: fixture.paths.settings) == 0o644)
    }

    @Test("Reactivation preserves an externally edited retired value")
    func reactivationPreservesEditedRetiredValue() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        try fixture.writeSettings(Data(#"{"theme":"dark"}"#.utf8), permissions: 0o600)
        var legacyEnvironment = fixture.managed.environment
        legacyEnvironment["CLAUDE_CODE_DISABLE_TELEMETRY"] = "true"
        let legacy = ClaudeCodeManagedSettings(
            model: fixture.managed.model,
            environment: legacyEnvironment
        )
        try fixture.manager.activate(managed: legacy)
        var current = try jsonObject(Data(contentsOf: fixture.paths.settings))
        var currentEnvironment = try #require(current["env"] as? [String: Any])
        currentEnvironment["CLAUDE_CODE_DISABLE_TELEMETRY"] = "manual"
        current["env"] = currentEnvironment
        try JSONSerialization.data(withJSONObject: current).write(to: fixture.paths.settings)

        try fixture.manager.activate(managed: fixture.managed)

        let root = try jsonObject(Data(contentsOf: fixture.paths.settings))
        let environment = try #require(root["env"] as? [String: Any])
        #expect(
            environment["CLAUDE_CODE_DISABLE_TELEMETRY"] as? String == "manual"
        )
        try fixture.manager.restore()
        let restored = try jsonObject(Data(contentsOf: fixture.paths.settings))
        let restoredEnvironment = try #require(restored["env"] as? [String: Any])
        #expect(
            restoredEnvironment["CLAUDE_CODE_DISABLE_TELEMETRY"] as? String == "manual"
        )
    }

    @Test(
        "An interrupted migration retains old ownership until settings and journal converge",
        arguments: [false, true]
    )
    func interruptedMigration(migratedSettingsWereWritten: Bool) throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        let original = Data(#"{"theme":"dark"}"#.utf8)
        try fixture.writeSettings(original, permissions: 0o640)
        var legacyEnvironment = fixture.managed.environment
        legacyEnvironment["ANTHROPIC_MODEL"] = "provider/physical"
        legacyEnvironment["CLAUDE_CODE_SUBAGENT_MODEL"] = "provider/physical"
        let legacy = ClaudeCodeManagedSettings(
            model: "provider/physical",
            environment: legacyEnvironment
        )
        var supportedEnvironment = fixture.managed.environment
        supportedEnvironment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = ""
        supportedEnvironment["DISABLE_TELEMETRY"] = "1"
        let supported = ClaudeCodeManagedSettings(
            model: "claude-sonnet-5",
            environment: supportedEnvironment
        )

        try fixture.manager.activate(managed: legacy)
        let backup = try #require(fixture.backups().only)
        try journalData(
            settingsExisted: true,
            backupFilename: backup.lastPathComponent,
            originalPermissions: 0o640,
            managed: supported,
            previousManaged: [legacy]
        ).write(to: fixture.paths.restoreState)
        if migratedSettingsWereWritten {
            let current = try Data(contentsOf: fixture.paths.settings)
            let restored = try ClaudeCodeSettingsDocument.restoring(
                current: current,
                original: original,
                managed: legacy
            )
            let activated = try ClaudeCodeSettingsDocument.activating(
                restored,
                managed: supported
            )
            try activated.write(to: fixture.paths.settings)
        }

        #expect(try fixture.manager.status(expected: supported) == .drifted)
        try fixture.manager.activate(managed: supported)

        #expect(try fixture.manager.status(expected: supported) == .active)
        let root = try jsonObject(Data(contentsOf: fixture.paths.settings))
        let environment = try #require(root["env"] as? [String: Any])
        #expect(environment["ANTHROPIC_MODEL"] == nil)
        #expect(environment["CLAUDE_CODE_SUBAGENT_MODEL"] == nil)
        try fixture.manager.restore()
        #expect(try Data(contentsOf: fixture.paths.settings) == original)
        #expect(try permissions(of: fixture.paths.settings) == 0o640)
    }

    @Test("Concurrency hint migration preserves the original across repeated applies and restore")
    func concurrencyHintMigrationAndRepeatedApply() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        let original = Data(
            #"""
            {
              "theme": "dark",
              "env": {
                "CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": "user-subagents",
                "CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY": "user-tools"
              }
            }
            """#.utf8
        )
        try fixture.writeSettings(original, permissions: 0o640)
        let limitSeven = concurrencyManaged(fixture.managed, limit: 7)
        let limitEleven = concurrencyManaged(fixture.managed, limit: 11)

        try fixture.manager.activate(managed: fixture.managed)
        let originalBackup = try #require(fixture.backups().only)
        try fixture.manager.activate(managed: limitSeven)
        var environment = try #require(
            jsonObject(Data(contentsOf: fixture.paths.settings))["env"] as? [String: Any]
        )
        #expect(environment["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"] as? String == "7")
        #expect(environment["CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY"] as? String == "7")

        try fixture.manager.activate(managed: limitEleven)
        environment = try #require(
            jsonObject(Data(contentsOf: fixture.paths.settings))["env"] as? [String: Any]
        )
        #expect(environment["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"] as? String == "11")
        #expect(environment["CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY"] as? String == "11")
        #expect(try fixture.manager.status(expected: limitEleven) == .active)
        #expect(try fixture.backups() == [originalBackup])

        try fixture.manager.restore()
        #expect(try Data(contentsOf: fixture.paths.settings) == original)
        #expect(try permissions(of: fixture.paths.settings) == 0o640)
    }

    @Test("Disconnect preserves concurrency hint values that drifted from the managed signature")
    func concurrencyHintDriftOnRestore() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        try fixture.writeSettings(Data(#"{"theme":"dark"}"#.utf8), permissions: 0o600)
        let managed = concurrencyManaged(fixture.managed, limit: 7)
        try fixture.manager.activate(managed: managed)
        var root = try jsonObject(Data(contentsOf: fixture.paths.settings))
        var environment = try #require(root["env"] as? [String: Any])
        environment["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"] = "manual-subagents"
        environment["CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY"] = "manual-tools"
        root["env"] = environment
        try JSONSerialization.data(withJSONObject: root).write(to: fixture.paths.settings)

        try fixture.manager.restore()

        let restored = try jsonObject(Data(contentsOf: fixture.paths.settings))
        let restoredEnvironment = try #require(restored["env"] as? [String: Any])
        #expect(
            restoredEnvironment["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"] as? String
                == "manual-subagents"
        )
        #expect(
            restoredEnvironment["CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY"] as? String
                == "manual-tools"
        )
    }

    @Test("First ownership of concurrency hints preserves values added after connection")
    func concurrencyHintsAddedAfterConnection() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        try fixture.writeSettings(Data(#"{"theme":"dark"}"#.utf8), permissions: 0o600)
        try fixture.manager.activate(managed: fixture.managed)

        var current = try jsonObject(Data(contentsOf: fixture.paths.settings))
        var environment = try #require(current["env"] as? [String: Any])
        environment["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"] = "user-subagents"
        environment["CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY"] = "user-tools"
        current["env"] = environment
        try JSONSerialization.data(withJSONObject: current).write(to: fixture.paths.settings)

        let managed = concurrencyManaged(fixture.managed, limit: 7)
        try fixture.manager.activate(managed: managed)
        environment = try #require(
            jsonObject(Data(contentsOf: fixture.paths.settings))["env"] as? [String: Any]
        )
        #expect(environment["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"] as? String == "7")
        #expect(environment["CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY"] as? String == "7")

        try fixture.manager.restore()

        let restored = try jsonObject(Data(contentsOf: fixture.paths.settings))
        let restoredEnvironment = try #require(restored["env"] as? [String: Any])
        #expect(
            restoredEnvironment["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"] as? String
                == "user-subagents"
        )
        #expect(
            restoredEnvironment["CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY"] as? String
                == "user-tools"
        )
    }

    @Test("Reactivating an originally absent profile keeps an absent recovery baseline")
    func reactivationKeepsAbsentBaseline() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        try fixture.manager.activate(managed: fixture.managed)
        let updated = ClaudeCodeManagedSettings(
            model: "claude-opus-5",
            environment: fixture.managed.environment
        )

        try fixture.manager.activate(managed: updated)

        #expect(try fixture.backups().isEmpty)
        #expect(
            try ClaudeCodeSettingsDocument.isManaged(
                Data(contentsOf: fixture.paths.settings),
                managed: updated
            )
        )
        try fixture.manager.restore()
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.settings.path))
    }

    @Test("Reactivation adopts an external settings deletion as the recovery baseline")
    func reactivationAdoptsExternalDeletion() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        try fixture.writeSettings(Data(#"{"theme":"dark"}"#.utf8), permissions: 0o640)
        try fixture.manager.activate(managed: fixture.managed)
        let originalBackup = try #require(fixture.backups().only)
        try FileManager.default.removeItem(at: fixture.paths.settings)
        let updated = ClaudeCodeManagedSettings(
            model: "claude-opus-5",
            environment: fixture.managed.environment
        )

        try fixture.manager.activate(managed: updated)

        let journal = try jsonObject(Data(contentsOf: fixture.paths.restoreState))
        #expect(journal["settingsExisted"] as? Bool == false)
        #expect(journal["backupFilename"] == nil)
        #expect(journal["originalPermissions"] == nil)
        #expect(try fixture.backups() == [originalBackup])
        #expect(
            try ClaudeCodeSettingsDocument.isManaged(
                Data(contentsOf: fixture.paths.settings),
                managed: updated
            )
        )
        try fixture.manager.restore()
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.settings.path))
    }

    private func concurrencyManaged(
        _ managed: ClaudeCodeManagedSettings,
        limit: Int
    ) -> ClaudeCodeManagedSettings {
        var environment = managed.environment
        environment["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"] = String(limit)
        environment["CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY"] = String(limit)
        return ClaudeCodeManagedSettings(model: managed.model, environment: environment)
    }
}
