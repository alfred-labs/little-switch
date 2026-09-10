import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Claude Code profile")
struct ClaudeCodeProfileTests {
    @Test("Profile paths keep Claude settings and LittleSwitch recovery data separate")
    func paths() {
        let paths = ClaudeCodeProfilePaths(
            homeDirectory: URL(filePath: "/Users/test"),
            applicationSupport: URL(filePath: "/Users/test/Library/Application Support")
        )

        #expect(paths.settings.path == "/Users/test/.claude/settings.json")
        #expect(
            paths.restoreState.path
                == "/Users/test/Library/Application Support/LittleSwitch/ClaudeCode/restore.json"
        )
        #expect(
            paths.backupDirectory.path
                == "/Users/test/Library/Application Support/LittleSwitch/Backups/ClaudeCode"
        )
    }

    @Test("Live paths use the file manager home and require Application Support")
    func livePaths() throws {
        let fileManager = ProfilePathsFileManager(
            home: URL(filePath: "/Users/live"),
            applicationSupport: URL(filePath: "/Users/live/Library/Application Support")
        )
        #expect(
            try ClaudeCodeProfilePaths.live(fileManager: fileManager)
                == ClaudeCodeProfilePaths(
                    homeDirectory: URL(filePath: "/Users/live"),
                    applicationSupport: URL(
                        filePath: "/Users/live/Library/Application Support"
                    )
                )
        )

        fileManager.applicationSupport = nil
        #expect(throws: ClaudeCodeProfileManager.Error.applicationSupportUnavailable) {
            try ClaudeCodeProfilePaths.live(fileManager: fileManager)
        }
    }

    @Test("Disk store returns no entries for an absent backup directory")
    func absentBackupDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-absent-backups-\(UUID().uuidString)"
        )
        let store = DiskClaudeCodeProfileFileStore(backupDirectory: root)
        #expect(try store.contents(of: root).isEmpty)
    }

    @Test("Activation keeps an exact private backup and restoration recovers bytes and mode")
    func exactBackupAndRestore() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        let original = Data(#"{ "theme" : "private-original", "env" : { "KEEP" : "yes" } }"#.utf8)
        try fixture.writeSettings(original, permissions: 0o640)

        try fixture.manager.activate(managed: fixture.managed)

        let backup = try #require(fixture.backups().only)
        #expect(try Data(contentsOf: backup) == original)
        #expect(try permissions(of: backup) == 0o600)
        #expect(try permissions(of: fixture.paths.settings) == 0o600)
        #expect(try permissions(of: fixture.paths.restoreState) == 0o600)
        #expect(
            try ClaudeCodeSettingsDocument.isManaged(
                Data(contentsOf: fixture.paths.settings),
                managed: fixture.managed
            )
        )
        let journal = try String(contentsOf: fixture.paths.restoreState, encoding: .utf8)
        #expect(!journal.contains("private-original"))
        #expect(!journal.contains("KEEP"))

        try fixture.manager.restore()

        #expect(try Data(contentsOf: fixture.paths.settings) == original)
        #expect(try permissions(of: fixture.paths.settings) == 0o640)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
        #expect(try fixture.backups() == [backup])
    }

    @Test("An originally absent settings file is removed on restore")
    func absentOriginal() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }

        try fixture.manager.restore()

        try fixture.manager.activate(managed: fixture.managed)
        #expect(FileManager.default.fileExists(atPath: fixture.paths.settings.path))
        #expect(try fixture.backups().isEmpty)

        try fixture.manager.restore()

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.settings.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
    }

    @Test("Reactivation keeps the first backup and updates the managed signature")
    func reactivation() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        let original = Data(#"{"theme":"dark"}"#.utf8)
        try fixture.writeSettings(original, permissions: 0o644)
        try fixture.manager.activate(managed: fixture.managed)
        let firstBackup = try #require(fixture.backups().only)
        let updated = ClaudeCodeManagedSettings(
            model: "claude-opus-5",
            environment: fixture.managed.environment
        )

        try fixture.manager.activate(managed: updated)

        #expect(try fixture.backups() == [firstBackup])
        #expect(
            try ClaudeCodeSettingsDocument.isManaged(
                Data(contentsOf: fixture.paths.settings),
                managed: updated
            )
        )
        try fixture.manager.restore()
        #expect(try Data(contentsOf: fixture.paths.settings) == original)
        #expect(try permissions(of: fixture.paths.settings) == 0o644)
    }

    @Test("Reactivation removes an env key absent from the new managed settings")
    func reactivationRemovesRetiredEnvKey() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        let settings = fixture.paths.settings
        let original = Data(#"{"theme":"dark"}"#.utf8)
        try fixture.writeSettings(original, permissions: 0o644)

        var withToolSearch = fixture.managed
        withToolSearch.environment["ENABLE_TOOL_SEARCH"] = "true"
        try fixture.manager.activate(managed: withToolSearch)
        let envWhileManaged = try jsonObject(Data(contentsOf: settings))["env"] as? [String: Any]
        #expect(envWhileManaged?["ENABLE_TOOL_SEARCH"] as? String == "true")

        try fixture.manager.activate(managed: fixture.managed)
        let envAfter = try jsonObject(Data(contentsOf: settings))["env"] as? [String: Any]
        #expect(envAfter?["ENABLE_TOOL_SEARCH"] == nil)
        #expect(envAfter?["CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS"] == nil)

        try fixture.manager.restore()
        #expect(try Data(contentsOf: settings) == original)
    }

    @Test("Successful profile cycles retain only five exact backups")
    func backupRotation() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }

        for index in 0..<7 {
            let original = Data(#"{"cycle":\#(index)}"#.utf8)
            try fixture.writeSettings(original, permissions: 0o600)
            try fixture.manager.activate(managed: fixture.managed)
            try fixture.manager.restore()
        }

        #expect(try fixture.backups().count == 5)
    }

    @Test("Rotation retains the active backup when creation dates are equal")
    func equalDateBackupRotation() throws {
        let paths = memoryPaths()
        var files: [URL: FaultingClaudeCodeProfileFileStore.Entry] = [
            paths.settings: .init(
                data: Data(#"{"theme":"dark"}"#.utf8),
                permissions: 0o600
            )
        ]
        for index in 0..<7 {
            files[paths.backupDirectory.appending(path: "settings.json.old-\(index).backup")] =
                .init(data: Data("old-\(index)".utf8), permissions: 0o600)
        }
        let store = FaultingClaudeCodeProfileFileStore(files: files)
        let manager = ClaudeCodeProfileManager(paths: paths, fileStore: store)

        try manager.activate(managed: managedSettings())

        let retainedBackups = try store.contents(of: paths.backupDirectory)
        #expect(retainedBackups.count == 5)
        #expect(try manager.status(expected: managedSettings()) == .active)
    }

    @Test("Status distinguishes inactive, active, expected drift, and file drift")
    func status() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        #expect(try fixture.manager.status(expected: fixture.managed) == .inactive)

        try fixture.manager.activate(managed: fixture.managed)
        #expect(try fixture.manager.status(expected: fixture.managed) == .active)
        #expect(try fixture.manager.status(expected: nil) == .active)
        #expect(
            try fixture.manager.status(
                expected: ClaudeCodeManagedSettings(
                    model: "claude-opus-5",
                    environment: fixture.managed.environment
                )
            ) == .drifted
        )

        var root = try jsonObject(Data(contentsOf: fixture.paths.settings))
        root["model"] = "manual"
        try JSONSerialization.data(withJSONObject: root).write(to: fixture.paths.settings)
        #expect(try fixture.manager.status(expected: fixture.managed) == .drifted)
    }

    @Test("Restore preserves an external deletion")
    func externalDeletion() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        try fixture.writeSettings(Data(#"{"theme":"dark"}"#.utf8), permissions: 0o600)
        try fixture.manager.activate(managed: fixture.managed)
        try FileManager.default.removeItem(at: fixture.paths.settings)

        try fixture.manager.restore()

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.settings.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
    }

    @Test("Malformed settings are rejected before activation or restoration side effects")
    func malformedSettings() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        try fixture.writeSettings(Data("{".utf8), permissions: 0o600)

        #expect(throws: ClaudeCodeSettingsDocument.Error.invalidJSON) {
            try fixture.manager.activate(managed: fixture.managed)
        }
        #expect(try fixture.backups().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))

        try fixture.writeSettings(Data(#"{"theme":"dark"}"#.utf8), permissions: 0o600)
        try fixture.manager.activate(managed: fixture.managed)
        try Data("{".utf8).write(to: fixture.paths.settings)
        #expect(throws: ClaudeCodeSettingsDocument.Error.invalidJSON) {
            try fixture.manager.restore()
        }
        #expect(FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
    }

    @Test("Malformed, unsupported, unsafe, and incomplete journals fail explicitly")
    func invalidJournals() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.paths.restoreState.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try Data("{".utf8).write(to: fixture.paths.restoreState)
        #expect(throws: ClaudeCodeProfileManager.Error.invalidJournal) {
            try fixture.manager.status(expected: fixture.managed)
        }

        try journalData(version: 2, backupFilename: nil, managed: fixture.managed)
            .write(to: fixture.paths.restoreState)
        #expect(throws: ClaudeCodeProfileManager.Error.unsupportedJournalVersion(2)) {
            try fixture.manager.status(expected: fixture.managed)
        }

        try journalData(
            settingsExisted: true,
            backupFilename: "../settings.json",
            managed: fixture.managed
        ).write(to: fixture.paths.restoreState)
        #expect(throws: ClaudeCodeProfileManager.Error.invalidBackupFilename) {
            try fixture.manager.restore()
        }

        try journalData(
            settingsExisted: true,
            backupFilename: "missing.backup",
            managed: fixture.managed
        ).write(to: fixture.paths.restoreState)
        #expect(throws: ClaudeCodeProfileManager.Error.missingBackup) {
            try fixture.manager.restore()
        }

        try journalData(
            settingsExisted: false,
            backupFilename: "unexpected.backup",
            managed: fixture.managed
        ).write(to: fixture.paths.restoreState)
        #expect(throws: ClaudeCodeProfileManager.Error.invalidBackupFilename) {
            try fixture.manager.status(expected: fixture.managed)
        }
    }

    @Test("Every activation mutation rolls back to the exact starting state", arguments: [1, 2, 3])
    func activationRollback(failingMutation: Int) throws {
        let paths = memoryPaths()
        let original = Data(#"{"theme":"dark"}"#.utf8)
        let store = FaultingClaudeCodeProfileFileStore(
            files: [paths.settings: .init(data: original, permissions: 0o640)]
        )
        store.fail(onMutations: [failingMutation])
        let manager = ClaudeCodeProfileManager(paths: paths, fileStore: store)

        #expect(throws: FaultingClaudeCodeProfileFileStore.Error.injected) {
            try manager.activate(managed: managedSettings())
        }
        #expect(store.files == [paths.settings: .init(data: original, permissions: 0o640)])
    }

    @Test("Every restore mutation rolls back to the active state", arguments: [1, 2])
    func restoreRollback(failingMutation: Int) throws {
        let paths = memoryPaths()
        let original = Data(#"{"theme":"dark"}"#.utf8)
        let store = FaultingClaudeCodeProfileFileStore(
            files: [paths.settings: .init(data: original, permissions: 0o640)]
        )
        let manager = ClaudeCodeProfileManager(paths: paths, fileStore: store)
        try manager.activate(managed: managedSettings())
        let activeFiles = store.files
        store.fail(onMutations: [failingMutation])

        #expect(throws: FaultingClaudeCodeProfileFileStore.Error.injected) {
            try manager.restore()
        }
        #expect(store.files == activeFiles)
    }

    @Test("A failed rollback is reported distinctly")
    func rollbackFailure() {
        let paths = memoryPaths()
        let store = FaultingClaudeCodeProfileFileStore(
            files: [
                paths.settings: .init(
                    data: Data(#"{"theme":"dark"}"#.utf8),
                    permissions: 0o600
                )
            ]
        )
        store.fail(onMutations: [2, 3])
        let manager = ClaudeCodeProfileManager(paths: paths, fileStore: store)

        #expect(throws: ClaudeCodeProfileManager.Error.rollbackFailed) {
            try manager.activate(managed: managedSettings())
        }
    }

}
