import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenCode interrupted profile recovery")
struct OpenCodeProfileRecoveryTests {
    @Test(
        "Every durable migration state can restore or reapply without orphaning managed MCP entries",
        arguments: [false, true], [false, true]
    )
    func interruptedMigration(reapply: Bool, editedLegacyServer: Bool) throws {
        let paths = openCodeMemoryPaths()
        let original = Data(
            #"{"theme":"original","mcp":{"web":{"type":"local","command":["user-web"]}}}"#.utf8
        )
        let store = FaultingOpenCodeProfileFileStore(files: [
            paths.settings: .init(data: original, permissions: 0o640)
        ])
        var legacy = openCodeManagedSettings()
        legacy.mcp = .littleSwitch
        legacy.mcp?.name = "little-switch"
        var current = openCodeManagedSettings()
        current.mcp = .littleSwitch
        let manager = OpenCodeProfileManager(paths: paths, fileStore: store)
        try manager.activate(managed: legacy)
        var changed = try jsonObject(#require(store.files[paths.settings]?.data))
        var servers = try #require(changed["mcp"] as? [String: Any])
        servers["other"] = ["type": "local", "command": ["other"]]
        if editedLegacyServer {
            servers["little-switch"] = ["type": "local", "command": ["edited"]]
        }
        changed["mcp"] = servers
        try store.write(JSONSerialization.data(withJSONObject: changed), to: paths.settings, permissions: 0o600)
        let baselineCount = store.durableSnapshots.count

        try manager.activate(managed: current)

        var expected = try jsonObject(original)
        var expectedServers = try #require(expected["mcp"] as? [String: Any])
        expectedServers["other"] = ["type": "local", "command": ["other"]]
        if editedLegacyServer {
            expectedServers["little-switch"] = ["type": "local", "command": ["edited"]]
        }
        expected["mcp"] = expectedServers
        let expectedData = try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])
        for durableState in store.durableSnapshots.dropFirst(baselineCount) {
            let recoveredStore = FaultingOpenCodeProfileFileStore(files: durableState)
            let recovered = OpenCodeProfileManager(paths: paths, fileStore: recoveredStore)
            let journal = try jsonObject(#require(recoveredStore.files[paths.restoreState]?.data))
            if let previous = journal["previousManaged"] as? [[String: Any]], !previous.isEmpty {
                #expect(try recovered.status(expected: current) == .drifted)
            }
            if reapply {
                try recovered.activate(managed: current)
                #expect(try recovered.status(expected: current) == .active)
            }
            try recovered.restore()
            let restored = try jsonObject(#require(recoveredStore.files[paths.settings]?.data))
            #expect(try JSONSerialization.data(withJSONObject: restored, options: [.sortedKeys]) == expectedData)
            #expect(try recoveredStore.permissions(paths.settings) == 0o640)
            #expect(try recoveredStore.snapshot(paths.restoreState) == nil)
        }
    }
}
