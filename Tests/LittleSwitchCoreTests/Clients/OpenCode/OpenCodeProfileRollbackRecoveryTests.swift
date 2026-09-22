import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenCode interrupted migration rollback")
struct OpenCodeProfileRollbackRecoveryTests {
    private enum CommitError: Swift.Error, Equatable { case injected }

    @Test("Every durable state of a rejected commit remains recoverable", arguments: [false, true])
    func interruptedRollback(reapply: Bool) throws {
        let fixture = try Fixture.make()
        let before = fixture.store.files
        let baseline = fixture.store.durableSnapshots.count

        #expect(throws: CommitError.injected) {
            try fixture.manager.activate(managed: fixture.current) { throw CommitError.injected }
        }

        #expect(fixture.store.files == before)
        try assertRecoverable(fixture.store.durableSnapshots.dropFirst(baseline), fixture: fixture, reapply: reapply)
    }

    @Test(
        "A failure at any rollback write retains enough ownership to recover",
        arguments: [false, true], [1, 2, 3, 4]
    )
    func failedRollback(reapply: Bool, failingMutation: Int) throws {
        let fixture = try Fixture.make()
        let baseline = fixture.store.durableSnapshots.count
        var commits = 0

        #expect(throws: OpenCodeProfileManager.Error.rollbackFailed) {
            try fixture.manager.activate(managed: fixture.current) {
                commits += 1
                fixture.store.fail(onMutations: [failingMutation])
                throw CommitError.injected
            }
        }

        #expect(commits == 1)
        try assertRecoverable(fixture.store.durableSnapshots.dropFirst(baseline), fixture: fixture, reapply: reapply)
        try assertRecoverable([fixture.store.files], fixture: fixture, reapply: reapply)
    }

    private func assertRecoverable(
        _ states: some Sequence<[URL: FaultingOpenCodeProfileFileStore.Entry]>,
        fixture: Fixture,
        reapply: Bool
    ) throws {
        for state in states {
            let store = FaultingOpenCodeProfileFileStore(files: state)
            let recovered = OpenCodeProfileManager(paths: fixture.paths, fileStore: store)
            if reapply {
                try recovered.activate(managed: fixture.current)
                #expect(try recovered.status(expected: fixture.current) == .active)
            }
            try recovered.restore()
            let restored = try jsonObject(#require(store.files[fixture.paths.settings]?.data))
            #expect(try JSONSerialization.data(withJSONObject: restored, options: [.sortedKeys]) == fixture.expected)
            #expect(try store.permissions(fixture.paths.settings) == 0o640)
            #expect(try store.snapshot(fixture.paths.restoreState) == nil)
        }
    }

    private struct Fixture {
        let paths: OpenCodeProfilePaths
        let store: FaultingOpenCodeProfileFileStore
        let manager: OpenCodeProfileManager
        let current: OpenCodeManagedSettings
        let expected: Data

        static func make() throws -> Self {
            let paths = openCodeMemoryPaths()
            let original = Data(
                #"{"theme":"original","mcp":{"web":{"type":"local","command":["user-web"]}}}"#.utf8)
            let store = FaultingOpenCodeProfileFileStore(files: [
                paths.settings: .init(data: original, permissions: 0o640)
            ])
            let manager = OpenCodeProfileManager(paths: paths, fileStore: store)
            var legacy = openCodeManagedSettings()
            legacy.mcp = .littleSwitch
            legacy.mcp?.name = "little-switch"
            try manager.activate(managed: legacy)

            var edited = try jsonObject(#require(store.files[paths.settings]?.data))
            edited["theme"] = "edited"
            var servers = try #require(edited["mcp"] as? [String: Any])
            servers["other"] = ["type": "local", "command": ["user-other"]]
            edited["mcp"] = servers
            try store.write(JSONSerialization.data(withJSONObject: edited), to: paths.settings, permissions: 0o600)

            let expected: [String: Any] = [
                "theme": "edited",
                "mcp": [
                    "web": ["type": "local", "command": ["user-web"]],
                    "other": ["type": "local", "command": ["user-other"]],
                ],
            ]
            var current = openCodeManagedSettings(modelSuffix: "replacement")
            current.mcp = .littleSwitch
            return Self(
                paths: paths,
                store: store,
                manager: manager,
                current: current,
                expected: try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys]))
        }
    }
}
