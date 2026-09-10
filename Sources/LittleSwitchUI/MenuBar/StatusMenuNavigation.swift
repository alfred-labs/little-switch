import AppKit
import Observation

/// Menu presentation state. The controller persists tab choices.
@MainActor
@Observable
final class StatusMenuNavigation {
    private(set) var selectedTab: StatusMenuTab

    init(selectedTab: StatusMenuTab) { self.selectedTab = selectedTab }

    func select(_ tab: StatusMenuTab) {
        selectedTab = tab
    }
}

/// Native items are retained while navigating, so menu tracking and the
/// hosted model drafts survive a tab change. Shared footer commands remain visible.
@MainActor
struct StatusMenuContentItems {
    var overview: [NSMenuItem] = []
    var claude: [NSMenuItem] = []
    var codex: [NSMenuItem] = []

    func items(for tab: StatusMenuTab) -> [NSMenuItem] {
        switch tab {
        case .overview: overview
        case .claude: claude
        case .codex: codex
        }
    }

    func show(_ navigation: StatusMenuNavigation) {
        for tab in StatusMenuTab.allCases {
            setVisible(
                items(for: tab),
                visible: navigation.selectedTab == tab
            )
        }
    }

    private func setVisible(_ items: [NSMenuItem], visible: Bool) {
        for item in items {
            if let apply = item as? MenuApplyMenuItem {
                apply.setTabVisible(visible)
            } else {
                item.isHidden = !visible
            }
        }
    }
}
