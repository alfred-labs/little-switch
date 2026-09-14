import AppKit
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Native settings navigation")
struct NativeSettingsNavigationTests {
    @Test("Settings expose seven destinations with the approved native symbols")
    func destinations() {
        #expect(
            AppModel.Section.allCases.map(\.rawValue) == [
                "General", "Providers", "Web Search", "Monitoring", "Claude", "Codex", "OpenCode",
            ])
        #expect(
            AppModel.Section.allCases.prefix(4).map(\.systemImage) == [
                "slider.horizontal.3", "externaldrive.connected.to.line.below",
                "globe", "waveform.path.ecg",
            ])
        #expect(AppModel.SidebarGroup.allCases.flatMap(\.sections) == AppModel.Section.allCases)
    }

    @Test("Application appearance inherits the user's system preference")
    func systemAppearance() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        LittleSwitchAppearance.apply(to: window)
        #expect(window.appearance == nil)
    }
}
