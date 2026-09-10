import Foundation
import Testing

@Suite("Menu picker style")
struct MenuPickerStyleTests {
    @Test("Every menu picker uses the shared regular native style")
    func sharedMenuPickerStyle() throws {
        let callSiteFiles = [
            "Components/Settings/SettingsMappingRow.swift",
            "Features/Clients/ClaudeCode/ClaudeCodeSettingsView.swift",
            "Features/Providers/ProviderEditor.swift",
        ]

        for file in callSiteFiles {
            let source = try source(named: file)
            #expect(!source.contains(".pickerStyle(.menu)"))
            #expect(source.contains(".settingsMenuPicker("))
        }

        for file in [
            "Features/Clients/Claude/ClaudeSettingsView.swift", "Features/Clients/Codex/CodexSettingsView.swift",
            "Features/Clients/OpenCode/OpenCodeSettingsView.swift",
        ] {
            #expect(try source(named: file).contains("SettingsMappingRow("))
        }

        for file in try RepositorySources.uiFiles() where file.lastPathComponent != "SettingsLayout.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains(".pickerStyle(.menu)"))
        }

        let layout = try source(named: "Components/Settings/SettingsLayout.swift")
        #expect(layout.contains("static let menuPickerControlSize: ControlSize = .regular"))
        #expect(layout.contains("func settingsMenuPicker(width: CGFloat? = nil)"))
        #expect(layout.contains("pickerStyle(.menu)"))
        #expect(layout.contains(".controlSize(SettingsLayout.menuPickerControlSize)"))
    }

    private func source(named file: String) throws -> String {
        return try String(
            contentsOf: repository.appendingPathComponent("Sources/LittleSwitchUI/\(file)"),
            encoding: .utf8
        )
    }

    private var repository: URL {
        RepositorySources.root
    }
}
