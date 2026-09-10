import Foundation
import Testing

@testable import LittleSwitchUI

@Suite("Status menu tab store")
struct StatusMenuTabStoreTests {
    private let suiteName = "status-menu-tab-tests"

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    @MainActor
    @Test("A missing or unknown stored tab falls back to the overview")
    func missingTabFallsBackToOverview() {
        let defaults = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(
            StatusMenuTabStore(defaults: defaults, key: "missing").selectedTab == .overview
        )

        defaults.set("nonsense", forKey: "corrupt")
        #expect(
            StatusMenuTabStore(defaults: defaults, key: "corrupt").selectedTab == .overview
        )
    }

    @MainActor
    @Test("The selected tab round-trips across store instances")
    func selectedTabPersists() {
        let defaults = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = StatusMenuTabStore(defaults: defaults, key: "tab")
        store.selectedTab = .claude
        #expect(
            StatusMenuTabStore(defaults: defaults, key: "tab").selectedTab == .claude
        )

        store.selectedTab = .codex
        #expect(store.selectedTab == .codex)
        #expect(StatusMenuTab.allCases == [.overview, .claude, .codex])
        #expect(StatusMenuTab.allCases.map(\.id) == ["overview", "claude", "codex"])
    }
}
