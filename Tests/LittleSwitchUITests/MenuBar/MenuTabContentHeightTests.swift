import AppKit
import SwiftUI
import Testing

@testable import LittleSwitchUI

/// The menu tab views are hosted in fixed-frame `NSHostingView`s, and their
/// bodies carry no frame of their own — the hosting view's bounds size the
/// row — so `fittingSize` reports what SwiftUI actually lays out. A declared
/// height short of that clips the bottom of the tab in the menu; one in
/// excess pads it with dead space.
@MainActor
@Suite("Menu tab content height")
struct MenuTabContentHeightTests {
    @Test("The Claude tab's declared height matches the laid-out height")
    func claudeTabHeightMatchesLayout() {
        expectMatchingHeight(
            declared: MenuClaudeTabView.height,
            rootView: MenuClaudeTabView(
                model: AppModel(),
                onMapping: { _, _ in },
                onApplyClaude: { _, _ in },
                cancelTracking: {}
            )
        )
    }

    @Test("The Codex tab's declared height matches the laid-out height")
    func codexTabHeightMatchesLayout() {
        expectMatchingHeight(
            declared: MenuCodexTabView.height,
            rootView: MenuCodexTabView(
                model: AppModel(),
                onDefault: { _ in },
                onAutoReview: { _ in },
                onApplyCodex: {}
            )
        )
    }

    @Test("The switcher's declared height matches the laid-out height")
    func switcherHeightMatchesLayout() {
        expectMatchingHeight(
            declared: StatusMenuLayout.switcherHeight,
            rootView: MenuTabSwitcherView(
                navigation: StatusMenuNavigation(selectedTab: .overview),
                onSelect: { _ in },
                onShowSettings: {}
            )
        )
    }

    private func expectMatchingHeight(
        declared: CGFloat,
        rootView: some View
    ) {
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(x: 0, y: 0, width: StatusMenuLayout.width, height: declared)
        hosting.layoutSubtreeIfNeeded()

        #expect(declared == hosting.fittingSize.height)
    }
}
