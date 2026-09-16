import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Claude Code family profile migration")
struct ClaudeCodeFamilyProfileTests {
    @Test("Family menu migration and relabeling restore the user's original names and model")
    func restoresOriginal() throws {
        let fixture = try ClaudeCodeProfileFixture.make()
        defer { fixture.remove() }
        let original = Data(
            #"{"model":"user-model","env":{"ANTHROPIC_DEFAULT_SONNET_MODEL_NAME":"My model","USER_SETTING":"keep"}}"#
                .utf8
        )
        try fixture.writeSettings(original, permissions: 0o600)
        let legacy = ClaudeCodeManagedSettings(
            model: "claude-sonnet-5[1m]",
            environment: ["ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-5"]
        )
        let updated = ClaudeCodeManagedSettings(
            model: "sonnet",
            environment: [
                "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-5[1m]",
                "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "Sonnet 5 ↦ (1M context)",
                "ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION": "Via LittleSwitch",
            ]
        )
        try fixture.manager.activate(managed: legacy)
        try fixture.manager.activate(managed: updated)
        let relabeled = updated.withModelIndicator(.swap)
        try fixture.manager.activate(managed: relabeled)
        #expect(try ClaudeCodeSettingsDocument.isManaged(Data(contentsOf: fixture.paths.settings), managed: relabeled))
        #expect(try fixture.backups().count == 1)
        try fixture.manager.restore()
        #expect(try Data(contentsOf: fixture.paths.settings) == original)
    }
}
