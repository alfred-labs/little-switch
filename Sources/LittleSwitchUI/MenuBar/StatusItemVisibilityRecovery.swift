import AppKit
import LittleSwitchCommon
import LittleSwitchCore
import OSLog
import SwiftUI

enum StatusItemIdentity {
    static let autosaveName = ProductIdentity.bundleIdentifier + ".menu-bar"
}

@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let onToggleClaude: @MainActor () -> Void
    private let onToggleClaudeCode: @MainActor () -> Void
    private let onToggleCodex: @MainActor () -> Void
    private let onToggleOpenCode: @MainActor () -> Void
    private let onMapping: @MainActor (String, ModelMapping?) async -> Void
    private let onCodexDefault: @MainActor (ModelMapping?) async -> Void
    private let onCodexAutoReview: @MainActor (ModelMapping?) async -> Void
    private let onApplyClaude:
        @MainActor (
            AppModel.ClaudePrimaryAction?,
            AppModel.ClaudeCodePrimaryAction?
        ) async -> Void
    private let onApplyCodex: @MainActor () async -> Void
    private let onShowSettings: @MainActor () -> Void
    private let tabStore = StatusMenuTabStore()
    private let navigation: StatusMenuNavigation
    private var statusItem: NSStatusItem?
    private var gatewayActivityItem: NSMenuItem?
    private var contentItems = StatusMenuContentItems()
    private var lastRenderedGatewayActivity: GatewayActivityPresentation?
    private var lastRenderedIconState: StatusItemIconState?
    private var visibilityTask: Task<Void, Never>?
    private var statusItemRecoveryPolicy = StatusItemVisibilityRecoveryPolicy()
    private let logger = Logger(
        subsystem: ProductIdentity.logSubsystem,
        category: "menu-bar"
    )

    init(
        model: AppModel,
        onToggleClaude: @escaping @MainActor () -> Void,
        onToggleClaudeCode: @escaping @MainActor () -> Void,
        onToggleCodex: @escaping @MainActor () -> Void,
        onToggleOpenCode: @escaping @MainActor () -> Void,
        onMapping: @escaping @MainActor (String, ModelMapping?) async -> Void,
        onCodexDefault: @escaping @MainActor (ModelMapping?) async -> Void,
        onCodexAutoReview: @escaping @MainActor (ModelMapping?) async -> Void,
        onApplyClaude:
            @escaping @MainActor (
                AppModel.ClaudePrimaryAction?,
                AppModel.ClaudeCodePrimaryAction?
            ) async -> Void,
        onApplyCodex: @escaping @MainActor () async -> Void,
        onShowSettings: @escaping @MainActor () -> Void = {
            NSApp.sendAction(
                #selector(LittleSwitchApplicationDelegate.showMainWindow),
                to: NSApp.delegate,
                from: nil
            )
        }
    ) {
        self.model = model
        self.onToggleClaude = onToggleClaude
        self.onToggleClaudeCode = onToggleClaudeCode
        self.onToggleCodex = onToggleCodex
        self.onToggleOpenCode = onToggleOpenCode
        self.onMapping = onMapping
        self.onCodexDefault = onCodexDefault
        self.onCodexAutoReview = onCodexAutoReview
        self.onApplyClaude = onApplyClaude
        self.onApplyCodex = onApplyCodex
        self.onShowSettings = onShowSettings
        navigation = StatusMenuNavigation(selectedTab: tabStore.selectedTab)
    }

    func start() {
        guard statusItem == nil else {
            return
        }
        buildMenu()
        scheduleVisibilityCheck(after: .seconds(3))
    }

    func applicationDidBecomeActive() {
        scheduleVisibilityCheck(after: .seconds(1))
    }

    func settingsWindowDidShow() {
        scheduleVisibilityCheck(after: .seconds(1))
    }

    func stop() {
        visibilityTask?.cancel()
        visibilityTask = nil
    }

    /// Polling calls this twice a second. An unchanged presentation must not
    /// reach the item at all: even an in-place SwiftUI update invalidates the
    /// row, so the equality gate is what keeps an open menu perfectly still.
    func refreshGatewayActivity() {
        guard let gatewayActivityItem, !gatewayActivityItem.isHidden else {
            return
        }
        let presentation = model.gatewayActivityPresentation
        guard presentation != lastRenderedGatewayActivity else {
            return
        }
        GatewayActivityMenuItemRenderer.apply(presentation, to: gatewayActivityItem)
        lastRenderedGatewayActivity = presentation
    }

    /// The glyph carries state, so the same polling tick that refreshes the
    /// dashboard refreshes it. The equality gate is what keeps the status item
    /// still: rebuilding an unchanged image would redraw the menu bar twice a
    /// second for nothing.
    func refreshIcon() {
        let state = model.statusItemIconState
        guard state != lastRenderedIconState else {
            return
        }
        statusItem?.button?.image = StatusItemIcon.makeImage(for: state)
        lastRenderedIconState = state
    }

    /// Shows the tab's items and hides the others. AppKit re-lays-out the
    /// open menu as visibilities flip, so a switch never rebuilds anything:
    /// the items are built once and only their `isHidden` moves. Returning
    /// to the overview re-renders the dashboard once, because its item may
    /// have sat unrefreshed while hidden.
    private func select(_ tab: StatusMenuTab) {
        navigation.select(tab)
        tabStore.selectedTab = tab
        contentItems.show(navigation)
        // Unhiding re-attaches the row's view to the tracking menu window,
        // where the same deferred SwiftUI layout would show it blank.
        warmVisibleItems(of: tab)
        guard tab == .overview else {
            return
        }
        lastRenderedGatewayActivity = nil
        refreshGatewayActivity()
    }

    private func warmVisibleItems(of tab: StatusMenuTab) {
        let visibleItems = contentItems.items(for: tab)
        for item in visibleItems {
            guard let view = item.view else {
                continue
            }
            StatusMenuHostedViewWarmup.warm(view: view)
        }
    }

    private func hostingView<Content: View>(
        _ rootView: Content,
        height: CGFloat
    ) -> NSHostingView<Content> {
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(
            x: 0,
            y: 0,
            width: StatusMenuLayout.width,
            height: height
        )
        // Hosted views are built while the menu is closed, so their first
        // SwiftUI layout can otherwise wait for a display pass that event
        // tracking never runs — a cold row opens blank until the menu is
        // reopened. Warm each view as it is created.
        StatusMenuHostedViewWarmup.warm(view: hosting)
        return hosting
    }

    private func buildMenu() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = StatusItemIdentity.autosaveName
        statusItem.behavior = []
        statusItem.isVisible = true
        let iconState = model.statusItemIconState
        statusItem.button?.image = StatusItemIcon.makeImage(for: iconState)
        lastRenderedIconState = iconState
        statusItem.button?.setAccessibilityLabel("LittleSwitch")
        statusItem.button?.toolTip = "LittleSwitch"
        let menu = NSMenu()
        // Completes any SwiftUI layout the closed menu deferred (state
        // updates landed while no window displayed the rows) before AppKit
        // starts tracking, so no hosted row opens blank.
        menu.delegate = self
        // The exact effective appearance carries accessibility attributes
        // that its name can omit. Hosted SwiftUI views and template icons
        // resolve their label colors against this, so an unpinned menu
        // renders them with a light-appearance palette on its dark surface.
        menu.appearance = NSApp.effectiveAppearance
        let switcher = NSMenuItem()
        switcher.view = hostingView(
            MenuTabSwitcherView(
                navigation: navigation,
                onSelect: { [weak self] tab in self?.select(tab) },
                onShowSettings: { [weak self] in self?.showSettings() }
            ),
            height: StatusMenuLayout.switcherHeight
        )
        menu.addItem(switcher)
        let status = NSMenuItem()
        status.view = hostingView(
            MenuStatusView(
                model: model,
                onToggleClaude: onToggleClaude,
                onToggleClaudeCode: onToggleClaudeCode,
                onToggleCodex: onToggleCodex,
                onToggleOpenCode: onToggleOpenCode
            ),
            height: StatusMenuLayout.applicationBlockHeight
        )
        menu.addItem(status)
        let activitySeparator = NSMenuItem.separator()
        menu.addItem(activitySeparator)
        let delegate = NSApp.delegate
        // The dashboard is display-only: an actionless item never presents as
        // clickable, so hovering it cannot mask the footer commands below.
        let gatewayActivityItem = NSMenuItem(
            title: "",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(gatewayActivityItem)
        self.gatewayActivityItem = gatewayActivityItem
        lastRenderedGatewayActivity = nil
        refreshGatewayActivity()
        let claudeTab = MenuApplyMenuItem(
            applyAction: .claude(
                model: model,
                cancelTracking: { [weak menu] in menu?.cancelTrackingWithoutAnimation() },
                onApply: onApplyClaude
            )
        )
        claudeTab.view = hostingView(
            claudeTabContent(menu: menu),
            height: MenuClaudeTabView.height
        )
        menu.addItem(claudeTab)
        let codexTab = MenuApplyMenuItem(
            applyAction: .codex(model: model, onApply: onApplyCodex)
        )
        codexTab.view = hostingView(
            MenuCodexTabView(
                model: model,
                onDefault: onCodexDefault,
                onAutoReview: onCodexAutoReview,
                onApplyCodex: onApplyCodex
            ),
            height: MenuCodexTabView.height
        )
        menu.addItem(codexTab)
        let commands = StatusMenuCommands.makeItems(target: delegate)
        for item in commands { menu.addItem(item) }
        contentItems = StatusMenuContentItems(
            overview: [status, activitySeparator, gatewayActivityItem],
            claude: [claudeTab],
            codex: [codexTab]
        )
        contentItems.show(navigation)
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func scheduleVisibilityCheck(after delay: Duration) {
        visibilityTask?.cancel()
        visibilityTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else {
                return
            }
            visibilityTask = nil
            recoverStatusItemIfNeeded()
        }
    }

    private func recoverStatusItemIfNeeded() {
        let snapshot = statusItemVisibilitySnapshot()
        guard statusItemRecoveryPolicy.shouldRecreate(for: snapshot) else {
            return
        }
        logger.notice(
            """
            Recreating hidden status item: \
            api=\(snapshot.statusItemVisible, privacy: .public) \
            window=\(snapshot.windowVisible, privacy: .public) \
            occlusion=\(snapshot.occlusionVisible, privacy: .public)
            """
        )
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        gatewayActivityItem = nil
        contentItems = StatusMenuContentItems()
        buildMenu()
        scheduleVisibilityCheck(after: .seconds(1))
    }

    private func statusItemVisibilitySnapshot() -> StatusItemVisibilitySnapshot {
        guard let statusItem,
            let window = statusItem.button?.window
        else {
            return StatusItemVisibilitySnapshot(
                statusItemVisible: false,
                windowVisible: false,
                occlusionVisible: false
            )
        }
        return StatusItemVisibilitySnapshot(
            statusItemVisible: statusItem.isVisible,
            windowVisible: window.isVisible,
            occlusionVisible: window.occlusionState.contains(.visible)
        )
    }

}

extension StatusItemController {
    func showSettings(activateApplication: @MainActor () -> Void = { NSApp.activate() }) {
        // Keep the activation request inside the gear's user event. Deferring
        // it with window presentation can lose macOS's activation context.
        activateApplication()
        statusItem?.menu?.cancelTrackingWithoutAnimation()
        // MainActor tasks can run inside AppKit's nested event-tracking loop,
        // before closing the menu restores the previous application's focus.
        // The default mode resumes only after that tracking loop has ended.
        let onShowSettings = onShowSettings
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                onShowSettings()
            }
        }
    }

    private func claudeTabContent(menu: NSMenu) -> MenuClaudeTabView {
        MenuClaudeTabView(
            model: model,
            onMapping: onMapping,
            onApplyClaude: onApplyClaude
        ) { [weak menu] in
            menu?.cancelTrackingWithoutAnimation()
        }
    }
}
