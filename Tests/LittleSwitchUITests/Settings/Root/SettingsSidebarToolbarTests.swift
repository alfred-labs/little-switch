import Foundation
import Testing

@testable import LittleSwitchUI

@Suite("Settings sidebar toolbar")
struct SettingsSidebarToolbarTests {
    @Test("Sidebar toggle uses a native navigation toolbar item")
    func nativeSidebarToggle() throws {
        let source = try settingsSplitViewSource()

        #expect(source.contains("ToolbarItem(placement: .navigation)"))
        #expect(source.contains("isSidebarVisible.toggle()"))
        #expect(source.contains("Image(systemName: \"sidebar.left\")"))
        #expect(source.contains("\"Hide sidebar\""))
        #expect(source.contains("\"Show sidebar\""))
        #expect(source.contains(".buttonStyle(.borderless)"))
        #expect(source.contains("if #available(macOS 26.0, *)"))
        #expect(source.contains(".sharedBackgroundVisibility(.hidden)"))
        #expect(
            source.contains(
                ".padding(.leading, SettingsLayout.sidebarToggleToolbarLeadingPadding)"
            )
        )
        #expect(SettingsLayout.sidebarToggleToolbarLeadingPadding == 36)
        #expect(!source.contains("sidebarToggleTitlebarOffset"))
        #expect(!source.contains("sidebarToggleExpandedLeadingPadding"))
        #expect(!source.contains("sidebarToggleCollapsedLeadingPadding"))
    }

    private func settingsSplitViewSource() throws -> String {
        let repository = RepositorySources.root
        return try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/LittleSwitchUI/Settings/Root/SettingsSplitView.swift"
            ),
            encoding: .utf8
        )
    }
}
