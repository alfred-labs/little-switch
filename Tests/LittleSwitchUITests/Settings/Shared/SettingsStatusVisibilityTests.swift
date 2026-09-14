import AppKit
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Settings status visibility")
struct SettingsStatusVisibilityTests {
    init() { _ = NSApplication.shared }

    @Test("Connection text stays visible when a toolbar requests icons only")
    func connectionKeepsItsText() {
        let status = SettingsConnectionStatus(connected: true, title: "Desktop connected")
        let regular = NSHostingView(rootView: status)
        let iconToolbar = NSHostingView(rootView: status.labelStyle(.iconOnly))

        #expect(regular.fittingSize.width > 90)
        #expect(iconToolbar.fittingSize.width == regular.fittingSize.width)
    }

    @Test("Pending changes keep their explanation in an icon-only toolbar")
    func pendingKeepsItsText() {
        let regular = NSHostingView(rootView: SettingsPendingNotice())
        let iconToolbar = NSHostingView(rootView: SettingsPendingNotice().labelStyle(.iconOnly))

        #expect(regular.fittingSize.width > 100)
        #expect(iconToolbar.fittingSize.width == regular.fittingSize.width)
    }
}
