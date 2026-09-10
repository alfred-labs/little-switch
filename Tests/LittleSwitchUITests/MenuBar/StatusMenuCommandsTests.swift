import AppKit
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Status menu commands")
struct StatusMenuCommandsTests {
    init() { _ = NSApplication.shared }

    @Test("The gear opens Settings directly without changing the selected tab")
    func gearOpensSettings() async throws {
        for tab in StatusMenuTab.allCases {
            let navigation = StatusMenuNavigation(selectedTab: tab)
            var settingsCalls = 0
            var selections: [StatusMenuTab] = []
            let host = MenuControlTestHost(
                MenuTabSwitcherView(
                    navigation: navigation,
                    onSelect: { selections.append($0) },
                    onShowSettings: { settingsCalls += 1 }
                ),
                width: StatusMenuLayout.width,
                height: StatusMenuLayout.switcherHeight
            )
            defer { host.close() }
            try await host.activateAccessibility()

            #expect(try host.element(label: "Open Settings").accessibilityPerformPress())

            #expect(settingsCalls == 1)
            #expect(selections.isEmpty)
            #expect(navigation.selectedTab == tab)
        }
    }

    @Test("Global commands remain reachable through native shortcuts when hidden")
    func hiddenCommandShortcuts() throws {
        let recorder = StatusCommandRecorder()
        let items = StatusMenuCommands.makeItems(target: recorder)
        #expect(
            items.map(\.title) == ["Settings…", "", "About LittleSwitch", "Check for Updates…", "Quit LittleSwitch"])
        #expect(items.filter(\.isSeparatorItem).count == 1)
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            menu.addItem(item)
            item.isHidden = true
            if !item.keyEquivalent.isEmpty {
                item.action = #selector(StatusCommandRecorder.record(_:))
            }
        }
        for characters in [",", "q"] {
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .command,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: 0,
                    context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: characters,
                    isARepeat: false,
                    keyCode: 0
                ))
            #expect(menu.performKeyEquivalent(with: event))
        }
        #expect(recorder.titles == ["Settings…", "Quit LittleSwitch"])
    }

    @Test("Tab navigation disarms hidden Return actions and preserves the shared footer")
    func navigationPreservesFooterAndDisarmsHiddenApply() {
        let navigation = StatusMenuNavigation(selectedTab: .claude)
        let overview = NSMenuItem()
        let claude = MenuApplyMenuItem(applyAction: MenuApplyAction(isEnabled: true) {})
        let codex = MenuApplyMenuItem(applyAction: MenuApplyAction(isEnabled: true) {})
        let commands = StatusMenuCommands.makeItems(target: nil)
        let content = StatusMenuContentItems(
            overview: [overview], claude: [claude], codex: [codex]
        )
        let menu = NSMenu()
        for item in [overview, claude, codex] + commands { menu.addItem(item) }
        claude.setTracking(true)
        codex.setTracking(true)
        for tab in [StatusMenuTab.claude, .codex, .overview, .claude] {
            navigation.select(tab)
            content.show(navigation)

            #expect(navigation.selectedTab == tab)
            #expect(overview.isHidden == (tab != .overview))
            #expect(claude.isHidden == (tab != .claude))
            #expect(codex.isHidden == (tab != .codex))
            #expect(claude.keyEquivalent == (tab == .claude ? "\r" : ""))
            #expect(codex.keyEquivalent == (tab == .codex ? "\r" : ""))
            #expect(commands.map(\.isHidden) == [true, false, false, false, false])
            #expect(Array(menu.items.suffix(commands.count)) == commands)
        }
    }
}

@MainActor
private final class StatusCommandRecorder: NSObject {
    var titles: [String] = []
    @objc func record(_ sender: NSMenuItem) { titles.append(sender.title) }
}
