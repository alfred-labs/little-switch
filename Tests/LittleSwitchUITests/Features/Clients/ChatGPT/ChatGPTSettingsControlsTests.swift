import AppKit
import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("ChatGPT native settings controls", .appKitIsolation)
struct ChatGPTSettingsControlsTests {
    @Test("Connection details expose each label and its own value to accessibility")
    func connectionDetailsAccessibility() async throws {
        let model = AppModel(snapshot: .init(configuration: .init()))
        let host = MenuControlTestHost(
            ChatGPTSettingsView(
                model: model,
                onModel: { _ in },
                onApply: {},
                onConnect: {},
                onOpen: {},
                onDisconnect: {}
            ),
            width: 720,
            height: 788
        )
        defer { host.close() }
        try await host.activateAccessibility()

        let connection = try host.element(label: L10n.string("Enabled with"))
        #expect(connection.accessibilityValueDescription() == L10n.string("Codex"))
        let history = try host.element(label: L10n.string("Chat history"))
        #expect(history.accessibilityValueDescription() == L10n.string("On this Mac"))
    }

    @Test(
        "Applying warns about a relaunch only for a connected Chat with a pending change",
        arguments: [(false, false, false), (false, true, false), (true, false, false), (true, true, true)]
    )
    func relaunchNotice(connected: Bool, pending: Bool, expected: Bool) async throws {
        let provider = Provider(
            name: "Synthetic",
            baseURL: "http://127.0.0.1:12345",
            authMode: .none,
            models: [DiscoveredModel(id: "model")],
            status: .ready
        )
        var configuration = AppConfiguration(providers: [provider])
        configuration.chatgpt.model = .init(providerID: provider.id, modelID: "model")
        configuration.chatgpt.connected = connected
        let model = AppModel(snapshot: .init(configuration: configuration))
        model.hasPendingChatGPTChanges = pending
        let host = MenuControlTestHost(
            ChatGPTSettingsView(
                model: model,
                onModel: { _ in },
                onApply: {},
                onConnect: {},
                onOpen: {},
                onDisconnect: {}
            ),
            width: 720,
            height: 788
        )
        defer { host.close() }
        try await host.activateAccessibility()

        #expect(host.textContent.contains(L10n.string("Applying will relaunch ChatGPT.")) == expected)
    }

    @Test("Settings offers a dedicated Chat choice and explicit shared connection controls")
    func actions() async throws {
        let bootstrap = MenuControlTestHost(Text("ChatGPT controls test"))
        defer { bootstrap.close() }
        let provider = Provider(
            name: "Synthetic",
            baseURL: "http://127.0.0.1:12345",
            authMode: .none,
            models: [DiscoveredModel(id: "model")],
            status: .ready
        )
        let model = AppModel(snapshot: .init(configuration: .init(providers: [provider])))
        model.selectedSection = .chatGPT
        model.isChoosingChatModelForConnection = true
        model.configuration.chatgpt.model = .init(providerID: provider.id, modelID: "model")
        let opened = AsyncTestGate()
        let disconnected = AsyncTestGate()
        let applied = AsyncTestGate()
        let controller = NSHostingController(
            rootView: settings(
                model: model,
                onOpen: { await opened.open() },
                onDisconnect: { await disconnected.open() },
                onApply: { await applied.open() }
            )
        )
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        SettingsWindowChrome.apply(to: window)
        window.setContentSize(NSSize(width: 1_200, height: 840))
        controller.view.layoutSubtreeIfNeeded()
        try await bootstrap.activateAccessibility()

        let connect = try await button(L10n.string("Connect Codex and ChatGPT"), in: window)
        #expect(connect.isAccessibilityEnabled())
        #expect(connect.accessibilityPerformPress())
        try await opened.wait(description: "ChatGPT connect callback")

        var connected = CoordinatorSnapshot(configuration: model.configuration, monitoringSnapshotSequence: 1)
        connected.configuration.chatgpt.connected = true
        connected.configuration.codex.connected = true
        connected.chatGPTStatus = .connected
        model.apply(connected)
        let reload = try await button(L10n.string("Reload Codex and ChatGPT"), in: window)
        #expect(reload.isAccessibilityEnabled())
        let disconnect = try await button(L10n.string("Disconnect Codex and ChatGPT"), in: window)
        #expect(disconnect.accessibilityPerformPress())
        try await disconnected.wait(description: "ChatGPT disconnect callback")

        model.isBusy = true
        let disabled = try await button(L10n.string("Reload Codex and ChatGPT"), in: window)
        #expect(!disabled.isAccessibilityEnabled())
        model.isBusy = false
        model.hasPendingChatGPTChanges = true
        let apply = try await button(L10n.string("Apply"), in: window)
        #expect(apply.isAccessibilityEnabled())
        #expect(apply.accessibilityPerformPress())
        try await applied.wait(description: "Chat model Apply callback")
        let pendingReload = try await button(L10n.string("Reload Codex and ChatGPT"), in: window)
        #expect(!pendingReload.isAccessibilityEnabled())
    }

    private func button(_ label: String, in window: NSWindow) async throws -> MenuControlAccessibilityElement {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        repeat {
            window.contentView?.layoutSubtreeIfNeeded()
            let roots: [AnyObject] =
                [window.contentView].compactMap(\.self)
                + SettingsToolbarTestSupport.views(in: window.toolbar?.items ?? [])
            if let match = descendants(roots).first(where: {
                $0.accessibilityRole() == .button && $0.accessibilityLabel() == label
            }) {
                return match
            }
            try await Task.sleep(for: .milliseconds(16))
        } while ContinuousClock.now < deadline
        throw AsyncTestTimeout(operation: "ChatGPT settings button: \(label)")
    }

    private func descendants(_ roots: [AnyObject]) -> [MenuControlAccessibilityElement] {
        var pending: [Any] = roots
        var visited = Set<ObjectIdentifier>()
        var result: [MenuControlAccessibilityElement] = []
        while let next = pending.popLast() {
            let object = next as AnyObject
            guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let element = MenuControlAccessibilityElement(object: object)
            result.append(element)
            pending.append(contentsOf: element.accessibilityChildren())
        }
        return result
    }

    private func settings(
        model: AppModel,
        onOpen: @escaping @MainActor () async -> Void,
        onDisconnect: @escaping @MainActor () async -> Void,
        onApply: @escaping @MainActor () async -> Void
    ) -> SettingsView {
        SettingsView(
            model: model,
            updater: DisabledSoftwareUpdateController(availability: .disabled(reason: "Synthetic test")),
            onLaunchAtLoginEnabled: { _ in },
            onOpenLoginItems: {},
            onModelIndicator: { _ in },
            onSaveProvider: { _ in .failed("Unused") },
            onTestProvider: { _ in .authenticationFailed("Unused") },
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
            onConnectCodex: onOpen,
            onApplyCodex: {},
            onOpenCodeDefault: { _ in },
            onConnectOpenCode: {},
            onApplyOpenCode: {},
            onRestoreOpenCode: {},
            onOpenChatGPT: onOpen,
            onDisconnectChatGPT: onDisconnect,
            onApplyChatGPT: onApply
        )
    }
}
