import AppKit
import LittleSwitchCore
import SwiftUI

@MainActor
public final class LittleSwitchApplicationDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let trafficStore: TrafficLogStore
    let usageHistoryStore = GatewayUsageHistoryStore()
    private let claudeController = NSWorkspaceClaudeController()
    private let codexController = NSWorkspaceCodexController()
    private let handoffCoordinator: ApplicationHandoffCoordinator
    let launchAtLoginController: LaunchAtLoginController
    private let signalMonitor = ApplicationHandoffSignalMonitor()
    var coordinator: ApplicationCoordinator?
    var statusItemController: StatusItemController?
    var softwareUpdater: any SoftwareUpdateProviding = DisabledSoftwareUpdateController(
        availability: .disabled(reason: "Software updates have not started.")
    )
    private var settingsWindow: NSWindow?
    private var startupTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    var terminationState = ApplicationTerminationState()
    private var terminationStarted = false

    override public init() {
        let current = ApplicationProcessIdentity(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            launchDate: NSRunningApplication.current.launchDate ?? Date()
        )
        handoffCoordinator = ApplicationHandoffCoordinator(
            current: current,
            discovery: NSWorkspaceApplicationProcessDiscovery(),
            signaler: POSIXApplicationProcessSignaler(),
            timing: ContinuousApplicationHandoffTiming()
        )
        launchAtLoginController = LaunchAtLoginController(
            service: ServiceManagementLaunchAtLoginService()
        )
        trafficStore = TrafficLogStore(usageRecorder: usageHistoryStore)
        super.init()
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        _ = notification
        LittleSwitchAppearance.apply(to: NSApp)
        signalMonitor.start { [weak self] in
            self?.requestHandoffTermination()
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApp.setActivationPolicy(.accessory)
        startupTask = Task { [weak self] in
            await self?.acquireOwnershipAndStart()
        }
    }

    private func acquireOwnershipAndStart() async {
        do {
            switch try await handoffCoordinator.acquireOwnership() {
            case .owner:
                guard !Task.isCancelled else {
                    return
                }
                await startOwnedApplication()
            case .superseded:
                requestHandoffTermination()
            }
        } catch is CancellationError {
        } catch {
            startApplicationShell()
            presentStartupFailure(
                message: "Could not replace the existing LittleSwitch instance."
            )
            showMainWindow()
        }
    }

    private func startOwnedApplication() async {
        startApplicationShell()
        do {
            coordinator = try ApplicationCoordinator.live(
                claudeController: claudeController,
                codexController: codexController,
                trafficRecorder: trafficStore
            )
        } catch {
            presentStartupFailure(message: startupErrorMessage(for: error))
        }
        pollingTask = Task { await pollRequestCount() }
        await usageHistoryStore.start()
        await trafficStore.start()
        guard !Task.isCancelled else {
            return
        }
        await start()
    }

    private func startApplicationShell() {
        refreshLaunchAtLogin()
        guard statusItemController == nil else {
            return
        }
        NSApp.mainMenu = ApplicationMenuFactory.make()
        // Started before the settings window is built: Sparkle's property
        // setters require a started updater.
        let updater = SoftwareUpdateControllerFactory.make(
            bundleURL: { Bundle.main.bundleURL },
            isDeveloperIDSigned: { DeveloperIDSignatureProbe.isDeveloperIDSigned($0) },
            makeDisabledController: { availability in
                DisabledSoftwareUpdateController(availability: availability)
            },
            sparkleController: SparkleSoftwareUpdateController()
        )
        updater.start()
        softwareUpdater = updater
        let statusItemController = StatusItemController(
            model: model,
            onToggleClaude: { [weak self] in
                self?.toggleConnection()
            },
            onToggleClaudeCode: { [weak self] in
                self?.toggleClaudeCodeConnection()
            },
            onToggleCodex: { [weak self] in
                self?.toggleCodexConnection()
            },
            onToggleOpenCode: { [weak self] in
                self?.toggleOpenCodeConnection(restoring: self?.model.openCodeSwitchOn == true)
            },
            onMapping: { [weak self] routeID, mapping in
                await self?.setMapping(routeID: routeID, mapping: mapping)
            },
            onCodexDefault: { [weak self] mapping in
                await self?.setCodexDefault(mapping)
            },
            onCodexAutoReview: { [weak self] mapping in
                await self?.perform { try await $0.setCodexAutoReviewModel(mapping) }
            },
            onApplyClaude: { [weak self] desktopAction, codeAction in
                await self?.applyClaudeProducts(
                    desktopAction: desktopAction,
                    codeAction: codeAction
                )
            },
            onApplyCodex: { [weak self] in
                await self?.applyCodexSettings()
            }
        )
        statusItemController.start()
        self.statusItemController = statusItemController
        buildSettingsWindow()
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        _ = notification
        refreshLaunchAtLogin()
        statusItemController?.applicationDidBecomeActive()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationStarted else {
            return .terminateNow
        }
        guard confirmQuitDiscardingPendingChanges() else {
            return .terminateCancel
        }
        terminationStarted = true
        let startupTask = startupTask
        startupTask?.cancel()
        pollingTask?.cancel()
        signalMonitor.stop()
        statusItemController?.stop()
        Task {
            await startupTask?.value
            await coordinator?.shutdown(mode: terminationState.mode)
            await trafficStore.stop()
            await usageHistoryStore.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    public func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        _ = sender
        _ = flag
        showMainWindow()
        return true
    }

    @objc func showMainWindow() {
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // Activation is asynchronous. This explicit Settings request must also
        // raise an already-visible window above the other application's window.
        settingsWindow?.orderFrontRegardless()
        statusItemController?.settingsWindowDidShow()
    }

    // Menu target: the app menu's "Check for Updates…" item relies on
    // the responder chain; the status menu's item reaches this through
    // an explicit #selector.
    @objc func checkForUpdates(_ sender: Any?) {
        softwareUpdater.checkForUpdates(sender)
    }

    @objc func quit() {
        terminationState.request(.userQuit)
        NSApp.terminate(nil)
    }

    private func requestHandoffTermination() {
        terminationState.request(.handoff)
        NSApp.terminate(nil)
    }

    private func start() async {
        guard let coordinator else {
            return
        }
        model.isBusy = true
        do {
            model.apply(try await coordinator.start())
            model.updateGatewayActivity(await coordinator.gatewayActivity())
        } catch {
            let snapshot = await coordinator.snapshot()
            guard !Task.isCancelled else {
                return
            }
            presentStartupFailure(
                snapshot: snapshot,
                message: startupErrorMessage(for: error)
            )
        }
    }

}

extension LittleSwitchApplicationDelegate {
    private func toggleClaudeCodeConnection() {
        if model.claudeCodeSwitchOn {
            Task { await restoreClaudeCodeSettings() }
        } else {
            Task { await connectClaudeCode() }
        }
    }

    private func saveProvider(_ input: ProviderInput) async -> ProviderSaveOutcome {
        guard let coordinator else {
            return .failed("LittleSwitch is still starting up. Try again in a moment.")
        }
        model.isBusy = true
        do {
            model.apply(try await coordinator.saveProvider(input))
            return .saved
        } catch {
            // The editor is open as a sheet: presenting through the model
            // would queue the alert behind the sheet instead of showing it.
            model.isBusy = false
            return .failed(startupErrorMessage(for: error))
        }
    }

    private func setWebSearchDraft(_ input: WebSearchInput?) async {
        guard let coordinator else {
            return
        }
        model.apply(await coordinator.setWebSearchDraft(input))
    }

    private func saveWebSearch(_ input: WebSearchInput) async -> Bool {
        guard let coordinator else {
            return false
        }
        model.isBusy = true
        do {
            model.apply(try await coordinator.saveWebSearch(input))
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func refreshProvider(_ id: UUID) async {
        await perform { try await $0.refreshProvider(id: id) }
    }

    private func deleteProvider(_ id: UUID) async {
        await perform { try await $0.deleteProvider(id: id) }
    }

    private func setMapping(routeID: String, mapping: ModelMapping?) async {
        await perform {
            try await $0.setMapping(routeID: routeID, mapping: mapping)
        }
    }

    private func setClaudeCodeDefault(
        _ routeID: String?,
        contextMode: ClaudeCodeContextMode
    ) async {
        await perform {
            try await $0.setClaudeCodeDefaultModel(
                routeID,
                contextMode: contextMode
            )
        }
    }

    private func connectClaudeCode() async {
        guard confirm("Configure new Claude Code sessions to use LittleSwitch?") else {
            return
        }
        await perform { try await $0.connectClaudeCode() }
    }

    private func restoreClaudeCodeSettings() async {
        guard
            confirmDiscardingPendingChanges(
                "Restore the previous user-level Claude Code settings?",
                actionTitle: "Restore"
            )
        else {
            return
        }
        await perform { try await $0.restoreClaudeCodeSettings() }
    }

    private func setCodexExposure(
        _ mapping: [ModelMapping],
        exposed: Bool
    ) async {
        await perform {
            try await $0.setCodexModelsExposure(mapping, exposed: exposed)
        }
    }

    private func setCodexDefault(_ mapping: ModelMapping?) async {
        await perform { try await $0.setCodexDefaultModel(mapping) }
    }

    @discardableResult
    func perform(
        _ operation: (ApplicationCoordinator) async throws -> CoordinatorSnapshot
    ) async -> Bool {
        guard let coordinator else {
            return false
        }
        model.isBusy = true
        do {
            model.apply(try await operation(coordinator))
            return true
        } catch {
            present(error)
            return false
        }
    }

}

// The settings-window construction is the delegate's largest single
// member; keeping it in an extension holds the class body under the
// lint's type-body budget.
extension LittleSwitchApplicationDelegate {
    private func buildSettingsWindow() {
        let view = SettingsView(
            model: model,
            updater: softwareUpdater,
            onLaunchAtLoginEnabled: { [weak self] enabled in
                await self?.setLaunchAtLoginEnabled(enabled)
            },
            onOpenLoginItems: { [weak self] in
                self?.openLoginItemsSettings()
            },
            onModelIndicator: { [weak self] indicator in
                await self?.setModelIndicator(indicator)
            },
            onSaveProvider: { [weak self] input in
                await self?.saveProvider(input)
                    ?? .failed("LittleSwitch is unavailable. Try again in a moment.")
            },
            onTestProvider: { [weak self] input in
                await self?.testProvider(input)
                    ?? .authenticationFailed(
                        "LittleSwitch is unavailable. Try again in a moment."
                    )
            },
            onSaveWebSearch: { [weak self] input in
                await self?.saveWebSearch(input) ?? false
            },
            onWebSearchDraft: { [weak self] input in
                await self?.setWebSearchDraft(input)
            },
            onRefreshProvider: { [weak self] id in
                await self?.refreshProvider(id)
            },
            onDeleteProvider: { [weak self] id in
                await self?.deleteProvider(id)
            },
            onMapping: { [weak self] routeID, mapping in
                await self?.setMapping(routeID: routeID, mapping: mapping)
            },
            onAutoMode: { [weak self] enabled in
                await self?.setAutoMode(enabled)
            },
            onApplyClaudeProducts: { [weak self] desktopAction, codeAction in
                await self?.applyClaudeProducts(
                    desktopAction: desktopAction,
                    codeAction: codeAction
                )
            },
            onClaudeCodeDefault: { [weak self] routeID, contextMode in
                await self?.setClaudeCodeDefault(routeID, contextMode: contextMode)
            },
            onCodexExposure: { [weak self] mapping, exposed in
                await self?.setCodexExposure(mapping, exposed: exposed)
            },
            onCodexDefault: { [weak self] mapping in
                await self?.setCodexDefault(mapping)
            },
            onCodexAutoReview: { [weak self] mapping in
                await self?.perform { try await $0.setCodexAutoReviewModel(mapping) }
            },
            onConnectCodex: { [weak self] in
                await self?.connectCodex()
            },
            onApplyCodex: { [weak self] in
                await self?.applyCodexSettings()
            },
            onOpenCodeDefault: { [weak self] mapping in
                await self?.setOpenCodeDefault(mapping)
            },
            onConnectOpenCode: { [weak self] in
                await self?.connectOpenCode()
            },
            onApplyOpenCode: { [weak self] in
                await self?.applyOpenCodeSettings()
            },
            onRestoreOpenCode: { [weak self] in
                await self?.restoreOpenCodeSettings()
            },
            onMonitoringDraft: { [weak self] input in
                await self?.setMonitoringDraft(input)
            },
            onApplyMonitoring: { [weak self] input in
                await self?.applyMonitoring(input) ?? false
            },
            onTestMonitoring: { [weak self] in
                await self?.testMonitoringExport()
            }
        )
        settingsWindow = makeSettingsWindow(hosting: view)
    }

    private func makeSettingsWindow(hosting view: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsLayout.windowWidth,
                height: SettingsLayout.windowHeight
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
            ],
            backing: .buffered,
            defer: false
        )
        let controller = NSHostingController(rootView: view)
        // Let the SwiftUI content minimum own the native resize constraint.
        controller.sizingOptions = [.minSize]
        window.contentViewController = controller
        SettingsWindowChrome.apply(to: window)
        window.setFrame(
            NSRect(
                origin: window.frame.origin,
                size: NSSize(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight)
            ),
            display: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }
}
