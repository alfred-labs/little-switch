import Foundation
import LittleSwitchCore

/// The status menu's top-level switcher tabs.
enum StatusMenuTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case claude
    case codex

    var id: String { rawValue }
}

/// Seeds and persists the status menu's selected tab across launches.
@MainActor
final class StatusMenuTabStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = ProductIdentity.bundleIdentifier + ".status-menu-tab"
    ) {
        self.defaults = defaults
        self.key = key
    }

    var selectedTab: StatusMenuTab {
        get {
            StatusMenuTab(rawValue: defaults.string(forKey: key) ?? "") ?? .overview
        }
        set {
            defaults.set(newValue.rawValue, forKey: key)
        }
    }
}
