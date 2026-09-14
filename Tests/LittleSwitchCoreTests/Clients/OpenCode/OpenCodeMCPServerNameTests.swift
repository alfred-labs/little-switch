import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenCode MCP server name migration")
struct OpenCodeMCPServerNameTests {
    private enum CommitError: Swift.Error, Equatable {
        case injected
    }

    @Test("New profiles manage web and record its name only in the restore journal")
    func managedName() throws {
        let paths = openCodeMemoryPaths()
        let original = Data(#"{"mcp":{"little-switch":false,"web_search":false}}"#.utf8)
        let store = FaultingOpenCodeProfileFileStore(
            files: [paths.settings: .init(data: original, permissions: 0o640)]
        )
        let manager = OpenCodeProfileManager(paths: paths, fileStore: store)

        try manager.activate(managed: managed)

        let current = try jsonObject(#require(store.files[paths.settings]?.data))
        let servers = try #require(current["mcp"] as? [String: Any])
        #expect(
            servers as NSDictionary
                == ["web": serverObject, "little-switch": false, "web_search": false] as NSDictionary
        )
        let journal = try jsonObject(#require(store.files[paths.restoreState]?.data))
        let signature = try #require(journal["managed"] as? [String: Any])
        let owned = try #require(signature["mcp"] as? [String: Any])
        #expect(owned["name"] as? String == "web")
        #expect(try manager.status(expected: managed) == .active)

        try manager.restore()

        #expect(store.files[paths.settings] == .init(data: original, permissions: 0o640))
    }

    @Test("Legacy MCP values without a name retain little-switch ownership")
    func legacyNameDecoding() throws {
        let legacy = try legacyManaged()
        let recorded = try jsonObject(JSONEncoder().encode(#require(legacy.mcp)))
        #expect(recorded["name"] as? String == "little-switch")
        let initialized = OpenCodeManagedMCPServer(
            type: "remote", url: "https://127.0.0.1:11436/api/mcp", enabled: true, oauth: false, timeout: 150_000
        )
        #expect(initialized == legacy.mcp)
        let activated = try OpenCodeSettingsDocument.activating(nil, managed: legacy)
        #expect(try jsonObject(activated)["mcp"] as? NSDictionary == ["little-switch": serverObject] as NSDictionary)
        #expect(try OpenCodeSettingsDocument.isManaged(activated, managed: legacy))
        #expect(!(try OpenCodeSettingsDocument.isManaged(activated, managed: managed)))
    }

    @Test(
        "Renaming owns web while retaining previous restore values and unrelated edits", arguments: [false, true]
    )
    func migrationBaseline(oldEntryChanged: Bool) throws {
        let fixture = try fixture(oldEntryChanged: oldEntryChanged)
        let firstBackups = try fixture.store.contents(of: fixture.paths.backupDirectory)
        let originalBackup = try fixture.store.snapshot(#require(firstBackups.only))
        #expect(try fixture.manager.status(expected: managed) == .drifted)

        try fixture.manager.activate(managed: managed)

        #expect(try fixture.manager.status(expected: managed) == .active)
        #expect(try fixture.manager.managedSettings() == managed)
        let activated = try jsonObject(#require(fixture.store.files[fixture.paths.settings]?.data))
        var expectedServers = fixture.expectedServers
        expectedServers["web"] = serverObject
        #expect(activated["mcp"] as? NSDictionary == expectedServers as NSDictionary)
        #expect(try fixture.store.snapshot(#require(firstBackups.only)) == originalBackup)
        let journal = try fixture.store.snapshot(fixture.paths.restoreState)
        try fixture.manager.activate(managed: managed)
        #expect(try fixture.store.snapshot(fixture.paths.restoreState) == journal)

        try fixture.manager.restore()

        let restored = try #require(fixture.store.files[fixture.paths.settings])
        #expect(
            try jsonObject(restored.data) as NSDictionary
                == ["model": "before/model", "theme": "external", "mcp": fixture.expectedServers] as NSDictionary
        )
        #expect(restored.permissions == 0o640)
        #expect(fixture.store.files[fixture.paths.restoreState] == nil)
    }

    @Test("A named migration without original settings still restores file absence")
    func absentOriginal() throws {
        let paths = openCodeMemoryPaths()
        let store = FaultingOpenCodeProfileFileStore(files: [:])
        let manager = OpenCodeProfileManager(paths: paths, fileStore: store)
        try manager.activate(managed: legacyManaged())

        try manager.activate(managed: managed)
        #expect(try manager.status(expected: managed) == .active)
        try manager.restore()

        #expect(store.files.isEmpty)
    }

    @Test("Legacy Restore preserves a server the user renamed to web_search")
    func preserveExternalRename() throws {
        let paths = openCodeMemoryPaths()
        let store = FaultingOpenCodeProfileFileStore(files: [:])
        let manager = OpenCodeProfileManager(paths: paths, fileStore: store)
        try manager.activate(managed: legacyManaged())
        try removeJournalName(store: store, paths: paths)
        var current = try jsonObject(#require(store.files[paths.settings]?.data))
        current["mcp"] = ["web_search": serverObject]
        try store.write(encode(current), to: paths.settings, permissions: 0o660)

        try manager.restore()

        #expect(
            try jsonObject(#require(store.files[paths.settings]?.data)) as NSDictionary
                == ["mcp": ["web_search": serverObject]] as NSDictionary
        )
    }

    @Test("Each named migration write failure restores exact files and modes", arguments: [1, 2, 3])
    func writeFailure(failingMutation: Int) throws {
        let fixture = try fixture(oldEntryChanged: true)
        let before = fixture.store.files
        fixture.store.fail(onMutations: [failingMutation])

        #expect(throws: FaultingOpenCodeProfileFileStore.Error.injected) {
            try fixture.manager.activate(managed: managed)
        }

        #expect(fixture.store.files == before)
    }

    @Test("A failed configuration commit rolls back a named migration exactly")
    func commitFailure() throws {
        let fixture = try fixture(oldEntryChanged: true)
        let before = fixture.store.files

        #expect(throws: CommitError.injected) {
            try fixture.manager.activate(managed: managed) { throw CommitError.injected }
        }

        #expect(fixture.store.files == before)
    }

    private var managed: OpenCodeManagedSettings {
        var value = openCodeManagedSettings()
        value.mcp = .littleSwitch
        return value
    }

    private var serverObject: [String: Any] {
        [
            "type": "remote", "url": "https://127.0.0.1:11436/api/mcp", "enabled": true, "oauth": false,
            "timeout": 150_000,
        ]
    }

    private func legacyManaged() throws -> OpenCodeManagedSettings {
        var value = openCodeManagedSettings()
        value.mcp = try JSONDecoder().decode(OpenCodeManagedMCPServer.self, from: encode(serverObject))
        return value
    }

    private struct Fixture {
        var paths: OpenCodeProfilePaths
        var store: FaultingOpenCodeProfileFileStore
        var manager: OpenCodeProfileManager
        var expectedServers: [String: Any]
    }

    private func fixture(oldEntryChanged: Bool) throws -> Fixture {
        let paths = openCodeMemoryPaths()
        let original = Data(
            #"{"model":"before/model","mcp":{"little-switch":{"type":"local","command":["original"]},"web":false,"other":false}}"#
                .utf8
        )
        let store = FaultingOpenCodeProfileFileStore(
            files: [paths.settings: .init(data: original, permissions: 0o640)]
        )
        let manager = OpenCodeProfileManager(paths: paths, fileStore: store)
        try manager.activate(managed: legacyManaged())
        try removeJournalName(store: store, paths: paths)
        var current = try jsonObject(#require(store.files[paths.settings]?.data))
        var servers = try #require(current["mcp"] as? [String: Any])
        if oldEntryChanged {
            servers["little-switch"] = ["type": "local", "command": ["external-old"]]
        }
        servers["web"] = ["type": "local", "command": ["external-new"]]
        servers["web_search"] = serverObject
        current["mcp"] = servers
        current["theme"] = "external"
        try store.write(encode(current), to: paths.settings, permissions: 0o660)
        if !oldEntryChanged {
            servers["little-switch"] = ["type": "local", "command": ["original"]]
        }
        return Fixture(paths: paths, store: store, manager: manager, expectedServers: servers)
    }

    private func removeJournalName(store: FaultingOpenCodeProfileFileStore, paths: OpenCodeProfilePaths) throws {
        var journal = try jsonObject(#require(store.files[paths.restoreState]?.data))
        var signature = try #require(journal["managed"] as? [String: Any])
        var owned = try #require(signature["mcp"] as? [String: Any])
        owned.removeValue(forKey: "name")
        signature["mcp"] = owned
        journal["managed"] = signature
        try store.write(encode(journal), to: paths.restoreState, permissions: 0o400)
    }

    private func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
