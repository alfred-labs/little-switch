import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenCode profile permission fallbacks")
struct OpenCodeProfilePermissionFallbackTests {
    @Test("Restore uses private permissions when no prior mode is known")
    func restoreUnknownPermissions() throws {
        let paths = openCodeMemoryPaths()
        let managed = openCodeManagedSettings()
        let original = Data(#"{"theme":"dark"}"#.utf8)
        let backupFilename = "opencode.json.original.backup"
        let backupURL = paths.backupDirectory.appending(path: backupFilename)
        let active = try OpenCodeSettingsDocument.activating(original, managed: managed)
        let journal = try openCodeJournalData(
            settingsExisted: true,
            backupFilename: backupFilename,
            managed: managed
        )
        let store = FaultingOpenCodeProfileFileStore(
            files: [
                paths.settings: .init(data: active, permissions: nil),
                paths.restoreState: .init(data: journal, permissions: nil),
                backupURL: .init(data: original, permissions: nil),
            ]
        )
        let manager = OpenCodeProfileManager(paths: paths, fileStore: store)

        try manager.restore()

        #expect(store.files[paths.settings] == .init(data: original, permissions: 0o600))
        #expect(store.files[paths.restoreState] == nil)
    }

    @Test("Rollback uses private permissions when a snapshot mode is unknown")
    func rollbackUnknownPermissions() {
        let paths = openCodeMemoryPaths()
        let original = Data(#"{"theme":"dark"}"#.utf8)
        let store = FaultingOpenCodeProfileFileStore(
            files: [paths.settings: .init(data: original, permissions: nil)]
        )
        store.fail(onMutations: [2])
        let manager = OpenCodeProfileManager(paths: paths, fileStore: store)

        #expect(throws: FaultingOpenCodeProfileFileStore.Error.injected) {
            try manager.activate(managed: openCodeManagedSettings())
        }
        #expect(store.files == [paths.settings: .init(data: original, permissions: 0o600)])
    }
}
