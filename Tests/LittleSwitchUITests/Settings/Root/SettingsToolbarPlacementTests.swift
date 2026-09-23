import AppKit
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Settings toolbar placement", .appKitIsolation)
struct SettingsToolbarPlacementTests {
    init() { _ = NSApplication.shared }

    @Test("A title-free settings toolbar keeps its actions at the trailing edge", arguments: [760.0, 900.0, 1_200.0])
    func trailingActions(width: Double) throws {
        let controller = NSHostingController(
            rootView: SettingsSplitView(isSidebarVisible: .constant(true)) {
                Text("Sidebar")
            } detail: {
                Color.clear
                    .toolbar {
                        SettingsToolbarActions {
                            SettingsPendingNotice()
                            Button(L10n.string("Apply")) {}
                        }
                    }
            }
            .settingsWindowTitle(L10n.string("Claude"))
        )
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        SettingsWindowChrome.apply(to: window)
        window.setContentSize(NSSize(width: width, height: 520))
        controller.view.layoutSubtreeIfNeeded()
        window.contentView?.superview?.layoutSubtreeIfNeeded()

        let toolbar = try #require(window.toolbar)
        let items = toolbar.items.map(\.itemIdentifier)
        let spacer = try #require(items.firstIndex(of: .flexibleSpace))
        #expect(spacer > items.startIndex)
        #expect(spacer < items.endIndex - 1)
        #expect(window.titleVisibility == .hidden)
        let actions = try #require(toolbar.items.last)
        let views = SettingsToolbarTestSupport.views(in: [actions])
        try #require(!views.isEmpty)
        try #require(views.allSatisfy { $0.window === window })
        let frames = views.map { $0.convert($0.bounds, to: nil) }
        let frame = frames.reduce(NSRect.null) { $0.union($1) }
        #expect(!frame.isEmpty)
        #expect(frame.minX > width / 2 - 80)
        #expect(frame.maxX <= width)
    }
}
