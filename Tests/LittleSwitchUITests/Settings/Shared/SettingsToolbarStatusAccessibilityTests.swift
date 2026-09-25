import AppKit
import ApplicationServices
import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Settings toolbar status accessibility", .appKitIsolation)
struct SettingsToolbarStatusAccessibilityTests {
    private let provider = Provider(
        name: "Synthetic",
        baseURL: "http://127.0.0.1:12345",
        authMode: .none,
        models: [DiscoveredModel(id: "model")]
    )

    @Test(
        "Clearing pending changes removes the old status from the persistent toolbar group",
        arguments: [false, true]
    )
    func clearsPendingGroupLabel(initialPending: Bool) async throws {
        let bootstrap = MenuControlTestHost(Text("Accessibility initialization"))
        defer { bootstrap.close() }
        let previousApplication = NSWorkspace.shared.frontmostApplication
        let previousKeyWindow = NSApp.keyWindow
        let previousFirstResponder = previousKeyWindow?.firstResponder
        let model = AppModel(snapshot: snapshot(pending: initialPending, sequence: 1))
        model.selectedSection = .common
        let windowTitle = "Toolbar status accessibility test"
        let windowIdentifier = "\(windowTitle) \(UUID())"
        let window = SettingsWindowFactory.make(hosting: settingsView(model: model))
        window.setAccessibilityIdentifier(windowIdentifier)
        #expect(window.frame.size == NSSize(width: 1_200, height: 840))
        defer {
            let restoreFocus = window.isKeyWindow
            window.orderOut(nil)
            window.close()
            if restoreFocus, let previousKeyWindow, previousKeyWindow.isVisible {
                previousKeyWindow.makeKey()
                _ = previousKeyWindow.makeFirstResponder(previousFirstResponder)
            }
            if NSApp.isActive, let previousApplication {
                if previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    NSApp.yieldActivation(to: previousApplication)
                    _ = previousApplication.activate(options: [])
                }
            }
        }
        window.makeKeyAndOrderFront(nil)
        // A command-line host has no foreground application to yield activation
        // to it. This visible AX scenario deliberately takes focus, like About,
        // then restores the previous application in the defer above.
        NSApp.activate(ignoringOtherApps: true)
        try await waitForReadyWindow(window)
        try await bootstrap.activateAccessibility()
        let toolbar = try #require(window.toolbar)
        model.selectedSection = .claude
        let actionsView = try await waitForActions(in: toolbar)
        let actions = try #require(toolbar.items.last)
        let initialResponder = try #require(window.firstResponder)
        let initialStatus = initialPending ? L10n.string("Pending in Claude") : L10n.string("Connected")
        try await waitForStatus(
            initialStatus, in: actionsView)
        let initialAX = try await readAX(windowIdentifier: windowIdentifier, phase: "initial")
        #expect(initialAX.names.contains(initialStatus), "Native AX initial: \(initialAX)")

        model.apply(snapshot(pending: true, sequence: 2))
        try await waitForStatus(L10n.string("Pending in Claude"), in: actionsView)
        window.title = windowTitle
        let pendingAX = try await readAX(windowIdentifier: windowIdentifier, phase: "pending")
        #expect(pendingAX.names.contains(L10n.string("Pending in Claude")), "Native AX pending: \(pendingAX)")
        #expect(!pendingAX.names.contains(L10n.string("Connected")), "Native AX pending: \(pendingAX)")

        model.apply(snapshot(pending: false, sequence: 3))
        try await waitForStatus(L10n.string("Connected"), in: actionsView)

        let elements = descendants(of: actionsView)
        let apply = try #require(elements.first { $0.accessibilityRole() == .button })
        #expect(apply.accessibilityLabel() == L10n.string("Apply"))
        #expect(!apply.isAccessibilityEnabled())
        #expect(toolbar.items.last === actions)
        #expect(SettingsToolbarTestSupport.views(in: [actions]).contains { $0 === actionsView })
        #expect(window.firstResponder === initialResponder)

        let clearedAX = try await readAX(windowIdentifier: windowIdentifier, phase: "cleared")
        #expect(!clearedAX.names.contains(L10n.string("Pending in Claude")), "Native AX cleared: \(clearedAX)")
        #expect(
            clearedAX.nodes.contains { $0.role == kAXStaticTextRole && $0.names.contains(L10n.string("Connected")) })
        let nativeApply = try #require(
            clearedAX.nodes.first { $0.role == kAXButtonRole && $0.names.contains(L10n.string("Apply")) })
        #expect(nativeApply.enabled == false)

        // Inspect the named group and the channels exposed to users. Generated
        // subitem storage labels can differ from their native menu titles.
        let actionItems = SettingsToolbarTestSupport.items(in: [actions])
        let names =
            [actions.label]
            + actionItems.compactMap(\.toolTip)
            + actionItems.compactMap(\.menuFormRepresentation).flatMap { menuTitles(in: $0) }
            + accessibleStrings(in: actionItems.map { MenuControlAccessibilityElement(object: $0) } + elements)
        #expect(!names.contains(L10n.string("Pending in Claude")), "Toolbar presentation names: \(names)")
    }

    private func menuTitles(in item: NSMenuItem) -> [String] {
        [item.title] + (item.submenu?.items ?? []).flatMap { menuTitles(in: $0) }
    }

    private func readAX(windowIdentifier: String, phase: String) async throws -> ToolbarStatusAXSnapshot {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var snapshot = await Task.detached { ToolbarStatusAXSnapshot.read(windowIdentifier: windowIdentifier) }.value
        // The native representation can materialize after SwiftUI rendering.
        // Retry materialization only, never a stale semantic value.
        while !snapshot.isMaterialized, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(16))
            snapshot = await Task.detached { ToolbarStatusAXSnapshot.read(windowIdentifier: windowIdentifier) }.value
        }
        try #require(snapshot.isMaterialized, "Native AX \(phase): \(snapshot)")
        return snapshot
    }

    private func waitForReadyWindow(_ window: NSWindow) async throws {
        // Native AXWindows can omit a window ordered during the host's
        // activation transition. Exercise the same visible, key-window boundary
        // as Settings rather than assuming direct AX selectors prove readiness.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var ready = false
        repeat {
            ready =
                NSApp.isRunning && NSApp.isActive && window.isKeyWindow
                && window.isOnActiveSpace && window.occlusionState.contains(.visible)
            if ready { break }
            try await Task.sleep(for: .milliseconds(16))
        } while ContinuousClock.now < deadline
        let diagnostics =
            "active=\(NSApp.isActive), key=\(window.isKeyWindow), "
            + "onActiveSpace=\(window.isOnActiveSpace), occlusion=\(window.occlusionState.rawValue)"
        try #require(ready, "Test window not ready: \(diagnostics)")
    }

    private func waitForActions(in toolbar: NSToolbar) async throws -> NSView {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var actionsView: NSView?
        repeat {
            let views = SettingsToolbarTestSupport.views(in: Array(toolbar.items.suffix(1)))
            actionsView = views.first { view in
                descendants(of: view).contains { $0.accessibilityLabel() == L10n.string("Apply") }
            }
            if actionsView != nil { break }
            try await Task.sleep(for: .milliseconds(16))
        } while ContinuousClock.now < deadline
        return try #require(actionsView)
    }

    private func waitForStatus(_ text: String, in view: NSView) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var matched = false
        repeat {
            view.layoutSubtreeIfNeeded()
            view.window?.displayIfNeeded()
            matched = descendants(of: view).contains {
                $0.accessibilityRole() == .staticText && $0.accessibilityValue() as? String == text
            }
            if matched { break }
            try await Task.sleep(for: .milliseconds(16))
        } while ContinuousClock.now < deadline
        try #require(matched, "Toolbar did not render \(text): \(accessibleStrings(in: descendants(of: view)))")
    }

    private func accessibleStrings(in elements: [MenuControlAccessibilityElement]) -> [String] {
        elements.flatMap { element in
            [
                element.accessibilityLabel(), element.accessibilityValue() as? String,
                element.object.accessibilityTitle?(), element.object.accessibilityHelp?(),
            ].compactMap(\.self)
        }
    }

    private func descendants(of root: AnyObject) -> [MenuControlAccessibilityElement] {
        var pending: [Any] = [root]
        var visited = Set<ObjectIdentifier>()
        var elements: [MenuControlAccessibilityElement] = []
        while let candidate = pending.popLast() {
            let object = candidate as AnyObject
            guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let element = MenuControlAccessibilityElement(object: object)
            elements.append(element)
            pending.append(contentsOf: element.accessibilityChildren())
        }
        return elements
    }

    private func snapshot(pending: Bool, sequence: UInt64) -> CoordinatorSnapshot {
        CoordinatorSnapshot(
            configuration: AppConfiguration(
                providers: [provider],
                mappings: ["claude-sonnet-5": ModelMapping(providerID: provider.id, modelID: "model")],
                connected: true
            ),
            desktopApplications: .init(claude: .available),
            hasPendingClaudeDesktopChanges: pending,
            claudeCodeStatus: .connected,
            monitoringSnapshotSequence: sequence
        )
    }

    private func settingsView(model: AppModel) -> SettingsView {
        SettingsView(
            model: model,
            updater: DisabledSoftwareUpdateController(availability: .disabled(reason: "Synthetic test")),
            onLaunchAtLoginEnabled: { _ in },
            onOpenLoginItems: {},
            onModelIndicator: { _ in },
            onSaveProvider: { _ in .failed("Not used") },
            onTestProvider: { _ in .authenticationFailed("Not used") },
            onSaveWebSearch: { _ in false },
            onWebSearchDraft: { _ in },
            onRefreshProvider: { _ in },
            onDeleteProvider: { _ in },
            onMapping: { _, _ in },
            onAutoMode: { _ in },
            onApplyClaudeProducts: { _, _ in },
            onClaudeCodeDefault: { _, _ in },
            onCodexExposure: { _, _ in },
            onCodexDefault: { _ in },
            onCodexAutoReview: { _ in },
            onConnectCodex: {},
            onApplyCodex: {},
            onOpenCodeDefault: { _ in },
            onConnectOpenCode: {},
            onApplyOpenCode: {},
            onRestoreOpenCode: {}
        )
    }
}

private struct ToolbarStatusAXSnapshot: Sendable {
    let error: String?
    let nodes: [ToolbarStatusAXNode]

    var names: [String] { nodes.flatMap(\.names) }

    var isMaterialized: Bool {
        // Traversal records the toolbar root first. A named descendant proves
        // content exists without waiting for a particular status value.
        error == nil && nodes.dropFirst().contains { $0.names.contains { !$0.isEmpty } }
    }

    static func read(windowIdentifier: String) -> Self {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windowsValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowsValue)
        guard status == .success else {
            return Self(error: "Window request failed: \(status.rawValue)", nodes: [])
        }
        let windows = windowsValue as? [AXUIElement] ?? []
        guard let window = windows.first(where: { string(kAXIdentifierAttribute, of: $0) == windowIdentifier }) else {
            let identifiers = windows.map { string(kAXIdentifierAttribute, of: $0) ?? "<nil>" }
            return Self(
                error: "Missing test window among native windows: \(identifiers)",
                nodes: []
            )
        }
        var windowChildren: CFTypeRef?
        let childrenStatus = AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &windowChildren)
        guard childrenStatus == .success else {
            return Self(error: "Window children request failed: \(childrenStatus.rawValue)", nodes: [])
        }
        let children = windowChildren as? [AXUIElement] ?? []
        guard let toolbar = children.first(where: { string(kAXRoleAttribute, of: $0) == kAXToolbarRole }) else {
            return Self(error: "Missing native toolbar in test window", nodes: [])
        }
        var pending = [toolbar]
        var visited: [AXUIElement] = []
        var nodes: [ToolbarStatusAXNode] = []
        while let element = pending.popLast() {
            guard !visited.contains(where: { CFEqual($0, element) }) else { continue }
            visited.append(element)
            let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
                .compactMap { string($0, of: element) }
            var enabledValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledValue)
            nodes.append(
                ToolbarStatusAXNode(
                    role: string(kAXRoleAttribute, of: element), names: names, enabled: enabledValue as? Bool))
            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success {
                pending += childrenValue as? [AXUIElement] ?? []
            }
        }
        return Self(error: nil, nodes: nodes)
    }

    private static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

private struct ToolbarStatusAXNode: Sendable {
    let role: String?
    let names: [String]
    let enabled: Bool?
}
