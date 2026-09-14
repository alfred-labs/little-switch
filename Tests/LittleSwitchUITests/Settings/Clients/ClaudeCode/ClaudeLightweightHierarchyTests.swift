import Foundation
import Testing

@Suite("Claude lightweight hierarchy")
struct ClaudeLightweightHierarchyTests {
    @Test("Claude Code hides external drift copy but preserves actionable notices")
    func claudeCodeHidesExternalDriftCopy() throws {
        let codeSource = try source(named: "Settings/Clients/ClaudeCode/ClaudeCodeSettingsView.swift")

        #expect(!codeSource.contains("settings changed outside LittleSwitch"))
        #expect(!codeSource.contains("exclamationmark.triangle"))
        #expect(codeSource.contains("Previous user-level settings can be restored."))
        #expect(codeSource.contains("Recovery data is unavailable."))
    }

    private func source(named filename: String) throws -> String {
        let repository = RepositorySources.root
        return try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/LittleSwitchUI/\(filename)"
            ),
            encoding: .utf8
        )
    }
}
