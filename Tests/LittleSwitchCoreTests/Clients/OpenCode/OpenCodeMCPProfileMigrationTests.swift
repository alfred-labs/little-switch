import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenCode MCP profile migration")
struct OpenCodeMCPProfileMigrationTests {
    @Test(
        "Upgrade captures the current MCP baseline and preserves first-connection permissions",
        arguments: [false, true],
        [
            nil, "{}", #"{"web":false}"#,
            #"{"web":{"type":"local","command":["custom"]},"other":false}"#,
        ]
            as [String?]
    )
    func migrationBaseline(originallyExisted: Bool, mcpJSON: String?) throws {
        let fixture = try fixture(originallyExisted: originallyExisted)
        let firstBackups = try fixture.store.contents(of: fixture.paths.backupDirectory)
        let originalBackup = try firstBackups.first.flatMap { try fixture.store.snapshot($0) }
        var current = try jsonObject(#require(fixture.store.files[fixture.paths.settings]?.data))
        current["theme"] = "external"
        current["mcp"] = try mcpJSON.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) }
        try fixture.store.write(encode(current), to: fixture.paths.settings, permissions: 0o660)

        try fixture.manager.activate(managed: managed)

        #expect(try fixture.manager.status(expected: managed) == .active)
        #expect(try fixture.manager.managedSettings() == managed)
        let journalData = try #require(fixture.store.files[fixture.paths.restoreState]?.data)
        let journal = try jsonObject(journalData)
        let journalText = try #require(String(data: journalData, encoding: .utf8))
        let recordedManaged = try #require(journal["managed"] as? [String: Any])
        #expect(recordedManaged["mcp"] != nil)
        #expect(journal["mcp"] == nil)
        #expect(!journalText.contains("custom"))
        if let backup = firstBackups.first {
            #expect(try fixture.store.snapshot(backup) == originalBackup)
        }

        try fixture.manager.restore()

        var expected: [String: Any] = ["theme": "external"]
        if originallyExisted {
            expected["model"] = "before/model"
        }
        expected["mcp"] = current["mcp"]
        let restored = try #require(fixture.store.files[fixture.paths.settings])
        #expect(try jsonObject(restored.data) as NSDictionary == expected as NSDictionary)
        #expect(restored.permissions == (originallyExisted ? 0o640 : 0o660))
        #expect(fixture.store.files[fixture.paths.restoreState] == nil)
    }

    @Test("A legacy journal cannot claim an already matching MCP server")
    func matchingUnownedMCP() throws {
        let fixture = try fixture(originallyExisted: false)
        let modern = try OpenCodeSettingsDocument.activating(nil, managed: managed)
        try fixture.store.write(modern, to: fixture.paths.settings, permissions: 0o600)

        #expect(try fixture.manager.status(expected: nil) == .active)
        #expect(try fixture.manager.status(expected: managed) == .drifted)

        try fixture.manager.restore()

        let restored = try jsonObject(#require(fixture.store.files[fixture.paths.settings]?.data))
        #expect(Set(restored.keys) == ["mcp"])
        #expect(try restored["mcp"] as? NSDictionary == jsonObject(modern)["mcp"] as? NSDictionary)
    }

    @Test("Every ownership expansion mutation rolls back exact files and permissions", arguments: [1, 2, 3])
    func migrationRollback(failingMutation: Int) throws {
        let fixture = try fixture(originallyExisted: true)
        var current = try jsonObject(#require(fixture.store.files[fixture.paths.settings]?.data))
        current["mcp"] = ["web": ["type": "local", "command": ["custom"]]]
        try fixture.store.write(encode(current), to: fixture.paths.settings, permissions: 0o660)
        let before = fixture.store.files
        fixture.store.fail(onMutations: [failingMutation])

        #expect(throws: FaultingOpenCodeProfileFileStore.Error.injected) {
            try fixture.manager.activate(managed: managed)
        }
        #expect(fixture.store.files == before)
    }

    @Test("Reapplying a legacy signature rolls back newly owned MCP values", arguments: [false, true])
    func legacySignatureRollback(existingMCP: Bool) throws {
        let fixture = try fixture(originallyExisted: false)
        if existingMCP {
            var current = try jsonObject(#require(fixture.store.files[fixture.paths.settings]?.data))
            current["mcp"] = ["web": ["type": "local", "command": ["custom"]]]
            try fixture.store.write(encode(current), to: fixture.paths.settings, permissions: 0o600)
        }
        let before = try #require(fixture.store.files[fixture.paths.settings]?.data)
        try fixture.manager.activate(managed: managed)

        try fixture.manager.activate(managed: openCodeManagedSettings())

        let after = try #require(fixture.store.files[fixture.paths.settings]?.data)
        #expect(try jsonObject(after) as NSDictionary == jsonObject(before) as NSDictionary)
        #expect(try fixture.manager.managedSettings() == openCodeManagedSettings())
        #expect(try fixture.manager.status(expected: managed) == .drifted)
        #expect(try fixture.manager.status(expected: openCodeManagedSettings()) == .active)
    }

    @Test("Subsequent Apply keeps the MCP baseline and external drift survives Restore")
    func reactivationAndExternalDrift() throws {
        let fixture = try fixture(originallyExisted: true)
        var current = try jsonObject(#require(fixture.store.files[fixture.paths.settings]?.data))
        current["mcp"] = ["web": false]
        try fixture.store.write(encode(current), to: fixture.paths.settings, permissions: 0o600)
        try fixture.manager.activate(managed: managed)
        let journal = try fixture.store.snapshot(fixture.paths.restoreState)
        try fixture.manager.activate(managed: managed)
        #expect(try fixture.store.snapshot(fixture.paths.restoreState) == journal)

        current = try jsonObject(#require(fixture.store.files[fixture.paths.settings]?.data))
        current["mcp"] = ["web": ["type": "local", "command": ["external"]]]
        try fixture.store.write(encode(current), to: fixture.paths.settings, permissions: 0o600)
        #expect(try fixture.manager.status(expected: managed) == .drifted)

        try fixture.manager.restore()

        let restored = try jsonObject(#require(fixture.store.files[fixture.paths.settings]?.data))
        #expect(restored["mcp"] as? NSDictionary == current["mcp"] as? NSDictionary)
        #expect(restored["model"] as? String == "before/model")
    }

    @Test("A fresh MCP profile restores exact original bytes and permissions")
    func freshProfile() throws {
        let fixture = try OpenCodeProfileFixture.make()
        defer { fixture.remove() }
        let original = Data(#"{ "mcp" : { "web" : null, "other" : false }, "permission" : "ask" }"#.utf8)
        try fixture.writeSettings(original, permissions: 0o640)

        try fixture.manager.activate(managed: managed)

        #expect(try fixture.manager.status(expected: managed) == .active)
        #expect(try Data(contentsOf: #require(fixture.backups().only)) == original)
        #expect(try permissions(of: fixture.paths.settings) == 0o600)
        try fixture.manager.restore()
        #expect(try Data(contentsOf: fixture.paths.settings) == original)
        #expect(try permissions(of: fixture.paths.settings) == 0o640)
    }

    @Test("Upgrade respects an MCP container deleted after the legacy connection")
    func removedContainerBaseline() throws {
        let paths = openCodeMemoryPaths()
        let original = Data(#"{"mcp":{"web":false,"other":false}}"#.utf8)
        let store = FaultingOpenCodeProfileFileStore(
            files: [paths.settings: .init(data: original, permissions: 0o640)]
        )
        let manager = OpenCodeProfileManager(paths: paths, fileStore: store)
        try manager.activate(managed: openCodeManagedSettings())
        var current = try jsonObject(#require(store.files[paths.settings]?.data))
        current.removeValue(forKey: "mcp")
        try store.write(encode(current), to: paths.settings, permissions: 0o600)

        try manager.activate(managed: managed)
        try manager.restore()

        #expect(try jsonObject(#require(store.files[paths.settings]?.data)).isEmpty)
        #expect(store.files[paths.settings]?.permissions == 0o640)
    }

    @Test("An invalid MCP container blocks migration before any file mutation")
    func invalidMigration() throws {
        let fixture = try fixture(originallyExisted: true)
        var current = try jsonObject(#require(fixture.store.files[fixture.paths.settings]?.data))
        current["mcp"] = false
        try fixture.store.write(encode(current), to: fixture.paths.settings, permissions: 0o640)
        let before = fixture.store.files

        #expect(throws: OpenCodeSettingsDocument.Error.nonObjectMCP) {
            try fixture.manager.activate(managed: managed)
        }
        #expect(fixture.store.files == before)
    }

    @Test("Migration retains at most five backups and protects the new recovery baseline")
    func migrationBackupRetention() throws {
        let fixture = try fixture(originallyExisted: true)
        for index in 0..<4 {
            try fixture.store.write(
                Data("old".utf8),
                to: fixture.paths.backupDirectory.appending(path: "opencode.json.old-\(index).backup"),
                permissions: 0o600
            )
        }
        var current = try jsonObject(#require(fixture.store.files[fixture.paths.settings]?.data))
        current["mcp"] = ["web": false]
        try fixture.store.write(encode(current), to: fixture.paths.settings, permissions: 0o600)

        try fixture.manager.activate(managed: managed)

        #expect(try fixture.store.contents(of: fixture.paths.backupDirectory).count == 5)
        #expect(try fixture.manager.status(expected: managed) == .active)
        try fixture.manager.restore()
        let restored = try jsonObject(#require(fixture.store.files[fixture.paths.settings]?.data))
        #expect(restored["mcp"] as? NSDictionary == ["web": false] as NSDictionary)
    }

    private var managed: OpenCodeManagedSettings {
        var managed = openCodeManagedSettings()
        managed.mcp = .littleSwitch
        return managed
    }

    private struct Fixture {
        var paths: OpenCodeProfilePaths
        var store: FaultingOpenCodeProfileFileStore
        var manager: OpenCodeProfileManager
    }

    private func fixture(originallyExisted: Bool) throws -> Fixture {
        let paths = openCodeMemoryPaths()
        let original = Data(#"{"model":"before/model","theme":"original"}"#.utf8)
        let store = FaultingOpenCodeProfileFileStore(
            files: originallyExisted ? [paths.settings: .init(data: original, permissions: 0o640)] : [:]
        )
        let manager = OpenCodeProfileManager(paths: paths, fileStore: store)
        try manager.activate(managed: openCodeManagedSettings())
        return Fixture(paths: paths, store: store, manager: manager)
    }

    private func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
