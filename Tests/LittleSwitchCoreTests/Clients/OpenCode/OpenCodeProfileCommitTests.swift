import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenCode profile commit transaction")
struct OpenCodeProfileCommitTests {
    private enum CommitError: Swift.Error, Equatable {
        case injected
    }

    @Test("Commit observes the activated profile for both initial activation and reactivation")
    func successfulCommit() throws {
        let paths = openCodeMemoryPaths()
        let store = FaultingOpenCodeProfileFileStore(files: [:])
        let manager = OpenCodeProfileManager(paths: paths, fileStore: store)
        var observed: [OpenCodeManagedSettings?] = []
        let first = managed
        var second = openCodeManagedSettings(modelSuffix: "second")
        second.mcp = .littleSwitch

        try manager.activate(managed: first) {
            observed.append(try manager.managedSettings())
            #expect(try manager.status(expected: first) == .active)
        }
        try manager.activate(managed: second) {
            observed.append(try manager.managedSettings())
            #expect(try manager.status(expected: second) == .active)
        }

        #expect(observed == [first, second])
        #expect(try manager.managedSettings() == second)
    }

    @Test("Commit failure restores an initial activation exactly", arguments: [false, true])
    func initialCommitFailure(originallyExisted: Bool) throws {
        let paths = openCodeMemoryPaths()
        let original = Data(#"{ "theme" : "original" }"#.utf8)
        let store = FaultingOpenCodeProfileFileStore(
            files: originallyExisted ? [paths.settings: .init(data: original, permissions: 0o640)] : [:]
        )
        let manager = OpenCodeProfileManager(paths: paths, fileStore: store)
        let before = store.files

        #expect(throws: CommitError.injected) {
            try manager.activate(managed: managed) { throw CommitError.injected }
        }

        #expect(store.files == before)
        #expect(try manager.status(expected: managed) == .inactive)
    }

    @Test("Commit failure restores legacy or modern drift, journal and modes exactly", arguments: [false, true])
    func reactivationCommitFailure(legacy: Bool) throws {
        let fixture = try fixture(legacy: legacy)
        let before = fixture.store.files

        #expect(throws: CommitError.injected) {
            try fixture.manager.activate(managed: managed) { throw CommitError.injected }
        }

        #expect(fixture.store.files == before)
    }

    @Test(
        "A failed profile write never calls commit and restores exact files",
        arguments: [false, true], [1, 2, 3]
    )
    func writeFailureSkipsCommit(reactivating: Bool, failingMutation: Int) throws {
        let fixture = try fixture(legacy: true)
        if !reactivating {
            try fixture.manager.restore()
        }
        let before = fixture.store.files
        fixture.store.fail(onMutations: [failingMutation])
        var commits = 0

        #expect(throws: FaultingOpenCodeProfileFileStore.Error.injected) {
            try fixture.manager.activate(managed: managed) { commits += 1 }
        }

        #expect(commits == 0)
        #expect(fixture.store.files == before)
    }

    @Test("Rollback failure after a rejected commit remains explicit")
    func commitRollbackFailure() throws {
        let fixture = try fixture(legacy: true)
        fixture.store.fail(onMutations: [5])

        #expect(throws: OpenCodeProfileManager.Error.rollbackFailed) {
            try fixture.manager.activate(managed: managed) { throw CommitError.injected }
        }
    }

    @Test("Failure to finalize the migration journal rolls back before commit")
    func finalJournalWriteFailure() throws {
        let fixture = try fixture(legacy: true)
        let before = fixture.store.files
        fixture.store.fail(onMutations: [4])
        var commits = 0

        #expect(throws: FaultingOpenCodeProfileFileStore.Error.injected) {
            try fixture.manager.activate(managed: managed) { commits += 1 }
        }

        #expect(commits == 0)
        #expect(fixture.store.files == before)
    }

    private var managed: OpenCodeManagedSettings {
        var managed = openCodeManagedSettings()
        managed.mcp = .littleSwitch
        return managed
    }

    private struct Fixture {
        var store: FaultingOpenCodeProfileFileStore
        var manager: OpenCodeProfileManager
    }

    private func fixture(legacy: Bool) throws -> Fixture {
        let paths = openCodeMemoryPaths()
        let store = FaultingOpenCodeProfileFileStore(
            files: [paths.settings: .init(data: Data(#"{"theme":"original"}"#.utf8), permissions: 0o640)]
        )
        let manager = OpenCodeProfileManager(paths: paths, fileStore: store)
        try manager.activate(managed: legacy ? openCodeManagedSettings() : managed)
        var current = try jsonObject(#require(store.files[paths.settings]?.data))
        current["mcp"] = ["web": ["type": "local", "command": ["custom"]]]
        current["model"] = "external/model"
        try store.write(
            JSONSerialization.data(withJSONObject: current, options: [.sortedKeys]),
            to: paths.settings,
            permissions: 0o660
        )
        let journal = try #require(store.files[paths.restoreState]?.data)
        try store.write(journal, to: paths.restoreState, permissions: 0o400)
        return Fixture(store: store, manager: manager)
    }
}
