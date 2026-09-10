import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Claude Code profile permissions")
struct ClaudeCodeProfilePermissionsTests {
    @Test("Missing permission metadata falls back to a private file mode")
    func missingPermissionFallback() throws {
        let paths = memoryPaths()
        let managerStore = FaultingClaudeCodeProfileFileStore(files: [:])
        let manager = ClaudeCodeProfileManager(paths: paths, fileStore: managerStore)
        try manager.activate(managed: managedSettings())
        managerStore.hidePermissions(for: [paths.settings])
        try manager.restore()
        #expect(managerStore.files[paths.settings] == nil)

        let original = Data(#"{"theme":"dark"}"#.utf8)
        let rollbackStore = FaultingClaudeCodeProfileFileStore(
            files: [paths.settings: .init(data: original, permissions: 0o640)]
        )
        rollbackStore.hidePermissions(for: [paths.settings])
        rollbackStore.fail(onMutations: [2])
        let rollbackManager = ClaudeCodeProfileManager(paths: paths, fileStore: rollbackStore)
        #expect(throws: FaultingClaudeCodeProfileFileStore.Error.injected) {
            try rollbackManager.activate(managed: managedSettings())
        }
        #expect(
            rollbackStore.files
                == [paths.settings: .init(data: original, permissions: 0o600)]
        )
    }
}
