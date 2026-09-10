import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Claude Code profile recovery baseline")
struct ClaudeCodeProfileRecoveryBaselineTests {
    @Test("Reactivation preserves user settings added after an absent baseline")
    func reactivationPreservesUserSettingsAddedAfterConnection() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        try fixture.manager.activate(managed: fixture.managed)
        #expect(try fixture.backups().isEmpty)

        var externallyEdited = try jsonObject(Data(contentsOf: fixture.paths.settings))
        externallyEdited["theme"] = "dark"
        try JSONSerialization.data(withJSONObject: externallyEdited)
            .write(to: fixture.paths.settings)
        let updated = ClaudeCodeManagedSettings(
            model: "claude-opus-5",
            environment: fixture.managed.environment
        )

        try fixture.manager.activate(managed: updated)

        let recoveryBackup = try #require(fixture.backups().only)
        let recoveryBaseline = try Data(contentsOf: recoveryBackup)
        let recoveryObject = try jsonObject(recoveryBaseline)
        #expect(recoveryObject["theme"] as? String == "dark")
        #expect(recoveryObject["model"] == nil)
        #expect(recoveryObject["env"] == nil)
        let journal = try jsonObject(Data(contentsOf: fixture.paths.restoreState))
        #expect(journal["settingsExisted"] as? Bool == true)
        #expect(journal["backupFilename"] as? String == recoveryBackup.lastPathComponent)

        try fixture.manager.restore()

        #expect(try Data(contentsOf: fixture.paths.settings) == recoveryBaseline)
        #expect(try permissions(of: fixture.paths.settings) == 0o600)
        let restored = try jsonObject(Data(contentsOf: fixture.paths.settings))
        #expect(restored["theme"] as? String == "dark")
    }

    @Test("Reactivation retains journal permissions when current metadata is unavailable")
    func reactivationFallsBackToJournalPermissions() throws {
        let paths = memoryPaths()
        let original = Data(#"{"theme":"dark"}"#.utf8)
        let store = FaultingClaudeCodeProfileFileStore(
            files: [paths.settings: .init(data: original, permissions: 0o640)]
        )
        let manager = ClaudeCodeProfileManager(paths: paths, fileStore: store)
        let managed = managedSettings()
        try manager.activate(managed: managed)

        var externallyEdited = try jsonObject(
            try #require(store.files[paths.settings]?.data)
        )
        externallyEdited["theme"] = "light"
        try store.write(
            JSONSerialization.data(withJSONObject: externallyEdited),
            to: paths.settings,
            permissions: 0o600
        )
        store.hidePermissions(for: [paths.settings])
        let updated = ClaudeCodeManagedSettings(
            model: "claude-opus-5",
            environment: managed.environment
        )

        try manager.activate(managed: updated)

        let journal = try jsonObject(try #require(store.files[paths.restoreState]?.data))
        #expect((journal["originalPermissions"] as? NSNumber)?.intValue == 0o640)
        try manager.restore()
        let restored = try #require(store.files[paths.settings])
        #expect(restored.permissions == 0o640)
        #expect(try jsonObject(restored.data)["theme"] as? String == "light")
    }
}
