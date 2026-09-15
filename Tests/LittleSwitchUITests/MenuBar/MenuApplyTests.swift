import AppKit
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Menu Apply")
struct MenuApplyTests {
    init() {
        // NSMenu sends its target/action through NSApplication. Swift
        // Testing does not create an application for the test process.
        _ = NSApplication.shared
    }

    @Test("Return dispatches the current tab's action exactly once")
    func returnUsesCurrentAction() throws {
        var applied: [StatusMenuTab] = []
        let claude = makeItem(action: MenuApplyAction(isEnabled: true) { applied.append(.claude) })
        let codex = makeItem(action: MenuApplyAction(isEnabled: true) { applied.append(.codex) })
        let menu = NSMenu()
        menu.addItem(claude)
        menu.addItem(codex)
        claude.setTracking(true)
        codex.setTracking(true)
        codex.setTabVisible(false)

        #expect(menu.performKeyEquivalent(with: try keyEvent()))
        claude.setTabVisible(false)
        codex.setTabVisible(true)
        #expect(menu.performKeyEquivalent(with: try keyEvent()))
        codex.setTabVisible(false)
        #expect(!menu.performKeyEquivalent(with: try keyEvent()))
        #expect(applied == [.claude, .codex])
    }

    @Test("Return is available only in the open status menu")
    func shortcutIsScopedToOpenMenu() throws {
        var applyCount = 0
        let item = makeItem(action: MenuApplyAction(isEnabled: true) { applyCount += 1 })
        let menu = NSMenu()
        menu.addItem(item)
        #expect(!menu.performKeyEquivalent(with: try keyEvent()))

        item.setTracking(true)
        let otherMenu = NSMenu()
        #expect(!otherMenu.performKeyEquivalent(with: try keyEvent()))
        #expect(menu.performKeyEquivalent(with: try keyEvent()))

        item.setTracking(false)
        #expect(!menu.performKeyEquivalent(with: try keyEvent()))
        #expect(applyCount == 1)
    }

    @Test("Return follows native modifier rules and preserves other shortcuts")
    func unrelatedKeysAreIgnored() throws {
        var applyCount = 0
        let item = makeItem(action: MenuApplyAction(isEnabled: true) { applyCount += 1 })
        let menu = NSMenu()
        menu.addItem(item)
        item.setTracking(true)

        for modifiers: NSEvent.ModifierFlags in [.command, .control, .option] {
            #expect(
                !menu.performKeyEquivalent(with: try keyEvent(modifiers: modifiers)),
                "Unexpected Apply with modifier flags \(modifiers.rawValue)"
            )
        }
        #expect(!menu.performKeyEquivalent(with: try keyEvent(characters: "q")))
        #expect(applyCount == 0)

        // AppKit treats Shift-Return as the same menu key equivalent.
        #expect(menu.performKeyEquivalent(with: try keyEvent(modifiers: .shift)))
        #expect(applyCount == 1)
    }

    @Test("A disabled action never dispatches, including direct activation")
    func disabledActionDoesNotDispatch() throws {
        var applyCount = 0
        let action = MenuApplyAction(isEnabled: false) { applyCount += 1 }
        let item = makeItem(action: action)
        let menu = NSMenu()
        menu.addItem(item)
        item.setTracking(true)

        #expect(!menu.performKeyEquivalent(with: try keyEvent()))
        action()
        #expect(applyCount == 0)
    }

    @Test("Apply preserves the native Settings shortcut")
    func nativeShortcutsRemainAvailable() throws {
        let recorder = NativeActionRecorder()
        let menu = NSMenu()
        let apply = makeItem(action: MenuApplyAction(isEnabled: true) {})
        menu.addItem(apply)
        apply.setTracking(true)
        let settings = NSMenuItem(
            title: L10n.string("Settings…"), action: #selector(NativeActionRecorder.invoke), keyEquivalent: ","
        )
        settings.target = recorder
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)

        #expect(menu.performKeyEquivalent(with: try keyEvent(characters: ",", modifiers: .command)))
        #expect(recorder.count == 1)
    }

    @Test("A changed draft updates the native shortcut while its view stays enabled")
    func pendingDraftUpdatesShortcut() async {
        let model = AppModel()
        let item = makeItem(action: MenuApplyAction.codex(model: model) {})
        item.setTracking(true)
        #expect(item.keyEquivalent.isEmpty)
        #expect(item.isEnabled)

        model.hasPendingCodexChanges = true
        for _ in 0..<20 where item.keyEquivalent.isEmpty {
            await Task.yield()
        }
        #expect(item.keyEquivalent == "\r")

        model.isBusy = true
        for _ in 0..<20 where !item.keyEquivalent.isEmpty {
            await Task.yield()
        }
        #expect(item.keyEquivalent.isEmpty)
        #expect(item.isEnabled)
    }

    @Test("Claude and Codex retain their pending and busy availability rules")
    func existingAvailabilityIsPreserved() {
        let model = AppModel()
        func actions() -> [Bool] {
            let claude = MenuApplyAction.claude(
                model: model,
                cancelTracking: {},
                onApply: { _, _ in }
            )
            let codex = MenuApplyAction.codex(model: model) {}
            return [claude.isEnabled, codex.isEnabled]
        }

        #expect(actions() == [false, false])
        model.hasPendingClaudeMappings = true
        #expect(actions() == [true, false])
        model.hasPendingCodexChanges = true
        #expect(actions() == [true, true])
        model.isBusy = true
        #expect(actions() == [false, false])
        model.isBusy = false
        model.hasPendingClaudeMappings = false
        model.hasPendingCodexChanges = false
        #expect(actions() == [false, false])
    }

    @Test("Activation rechecks availability after the control was rendered")
    func availabilityStaysLive() {
        let model = AppModel()
        var applyCount = 0
        let action = MenuApplyAction(isEnabled: !model.isBusy) { applyCount += 1 }
        #expect(action.isEnabled)

        model.isBusy = true
        action()
        #expect(!action.isEnabled)
        #expect(applyCount == 0)

        model.isBusy = false
        action()
        #expect(applyCount == 1)
    }

    private func makeItem(action: MenuApplyAction) -> MenuApplyMenuItem {
        let item = MenuApplyMenuItem(applyAction: action)
        item.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 32))
        return item
    }

    private final class NativeActionRecorder: NSObject {
        var count = 0

        @objc func invoke() {
            count += 1
        }
    }

    private func keyEvent(
        characters: String = "\r",
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: 36
            )
        )
    }
}
