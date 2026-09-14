import AppKit
import Testing

@testable import LittleSwitchUI

@Suite("Application menu")
struct ApplicationMenuTests {
    @Test("Claude and Codex actions apply settings without restart guidance")
    func processNeutralClientActions() throws {
        let delegate = try [
            "Application/Lifecycle/LittleSwitchApplicationDelegate.swift",
            "Features/Clients/Claude/LittleSwitchApplicationDelegateClaudeProducts.swift",
            "Features/Clients/Codex/LittleSwitchApplicationDelegateCodexProducts.swift",
            "Features/Clients/OpenCode/LittleSwitchApplicationDelegateOpenCode.swift",
        ].map { try source(named: $0) }.joined()
        let appModel = try source(named: "Application/Presentation/AppModel.swift")
        let settingsViews = try [
            "Settings/Root/SettingsView.swift",
            "Settings/Clients/Codex/CodexSettingsView.swift",
            "Settings/Clients/ClaudeCode/ClaudeCodeSettingsView.swift",
            "Settings/Search/WebSearchSettingsView.swift",
        ].map { try source(named: $0) }

        #expect(delegate.contains("try await coordinator.connect()"))
        #expect(delegate.contains("try await $0.connectCodex()"))
        #expect(delegate.contains("try await $0.applyCodexSettings()"))
        #expect(delegate.contains("Apply these LittleSwitch settings to"))
        #expect(!delegate.contains("Connect Claude to LittleSwitch"))
        #expect(!appModel.contains("\"Connect Claude\""))
        #expect(!delegate.contains("ManualClientRestartNotice"))
        #expect(!delegate.localizedCaseInsensitiveContains("restart"))
        #expect(!appModel.localizedCaseInsensitiveContains("restart"))
        #expect(settingsViews.allSatisfy { !$0.localizedCaseInsensitiveContains("restart") })
    }

    @Test("Common never controls external processes or secrets")
    func commonGatewayAccessPolicy() throws {
        let common = try source(named: "Settings/General/CommonSettingsView.swift")

        #expect(!common.contains("NSWorkspace"))
        #expect(!common.localizedCaseInsensitiveContains("relaunch"))
        #expect(!common.localizedCaseInsensitiveContains("terminate"))
        #expect(!common.localizedCaseInsensitiveContains("keychain"))
        #expect(!common.localizedCaseInsensitiveContains("secretStore"))
    }

    @Test("Launch at login is owned by the delegate and isolated from Common")
    func launchAtLoginOwnership() throws {
        let main = try source(named: "Application/Lifecycle/LittleSwitchApplicationDelegate.swift")
        let actions = try source(named: "Features/General/LittleSwitchApplicationDelegateLaunchAtLogin.swift")
        let common = try source(named: "Settings/General/CommonSettingsView.swift")
        let controller = try source(named: "Platform/LoginItems/LaunchAtLoginController.swift")
        let adapter = try source(named: "Platform/LoginItems/ServiceManagementLaunchAtLoginService.swift")

        #expect(main.contains("launchAtLoginController"))
        #expect(main.contains("refreshLaunchAtLogin()"))
        #expect(main.contains("onLaunchAtLoginEnabled"))
        #expect(main.contains("onOpenLoginItems"))
        #expect(actions.contains("try launchAtLoginController.setEnabled(enabled)"))
        #expect(actions.contains("launchAtLoginController.openSystemSettings()"))
        #expect(!common.contains("ServiceManagement"))
        #expect(!controller.contains("ServiceManagement"))
        #expect(adapter.contains("import ServiceManagement"))
        #expect(adapter.contains("SMAppService.mainApp"))
    }

    @Test("Owned startup refreshes login state without showing Settings")
    func launchAtLoginHiddenStartup() throws {
        let source = try source(named: "Application/Lifecycle/LittleSwitchApplicationDelegate.swift")
        let ownedStart = try #require(
            source.range(of: "private func startOwnedApplication()")
        )
        let shell = try #require(
            source.range(
                of: "private func startApplicationShell()",
                range: ownedStart.upperBound..<source.endIndex
            )
        )
        let ownedBody = String(source[ownedStart.lowerBound..<shell.lowerBound])

        #expect(!ownedBody.contains("showMainWindow()"))
        #expect(source.contains("refreshLaunchAtLogin()"))
        #expect(source.contains("applicationDidBecomeActive"))
        #expect(source.contains("statusItemController?.applicationDidBecomeActive()"))
    }

    @Test("Application ownership is acquired before the runtime starts")
    func handoffPrecedesRuntimeStartup() throws {
        let source = try source(named: "Application/Lifecycle/LittleSwitchApplicationDelegate.swift")
        let signal = try #require(source.range(of: "signalMonitor.start"))
        let ownership = try #require(
            source.range(of: "try await handoffCoordinator.acquireOwnership()")
        )
        let runtime = try #require(
            source.range(of: "startOwnedApplication()", range: ownership.upperBound..<source.endIndex)
        )

        #expect(signal.lowerBound < ownership.lowerBound)
        #expect(ownership.lowerBound < runtime.lowerBound)
        #expect(source.contains("case .owner:"))
        #expect(
            source.contains(
                "await coordinator?.shutdown(mode: terminationState.mode)"
            )
        )
    }

    @Test("Status menu exposes a Settings command with its gear icon")
    @MainActor
    func statusMenuSettingsCommand() throws {
        let items = StatusMenuCommands.makeItems(target: nil)
        let settings = try #require(items.first { $0.title == "Settings…" })
        #expect(settings.action == #selector(LittleSwitchApplicationDelegate.showMainWindow))
        #expect(settings.image?.isTemplate == true)
        #expect(settings.keyEquivalent == ",")
        #expect(settings.keyEquivalentModifierMask == [.command])
        #expect(settings.allowsKeyEquivalentWhenHidden)
    }

    @Test("Status menu renders four independent application rows")
    func independentApplicationRows() throws {
        let repository = RepositorySources.root
        let menuSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/LittleSwitchUI/MenuBar/MenuStatusView.swift"
            ),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/LittleSwitchUI/MenuBar/StatusItemVisibilityRecovery.swift"
            ),
            encoding: .utf8
        )

        let claudeDesktop = try #require(menuSource.range(of: "name: \"Claude Desktop\""))
        let claudeCode = try #require(menuSource.range(of: "name: \"Claude Code\""))
        let codex = try #require(menuSource.range(of: "name: \"Codex\""))
        let openCode = try #require(menuSource.range(of: "name: \"OpenCode\""))
        #expect(claudeDesktop.lowerBound < claudeCode.lowerBound)
        #expect(claudeCode.lowerBound < codex.lowerBound)
        #expect(codex.lowerBound < openCode.lowerBound)
        #expect(
            menuSource.contains(
                "StatusMenuCopy.customModelCount(model.claudeCustomModelCount)"
            )
        )
        #expect(menuSource.contains("\"Applies to new terminal sessions\""))
        #expect(
            menuSource.contains(
                "StatusMenuCopy.customModelCount(model.codexCustomModelCount)"
            )
        )
        // Every draft-holding row reports its unapplied changes, Desktop's
        // staged remaps included: the disconnect that discards them is
        // triggered from this very menu.
        #expect(
            menuSource.components(separatedBy: "StatusMenuCopy.detail(").count == 5
        )
        #expect(menuSource.contains("hasPendingChanges: model.hasPendingClaudeMappings"))
        #expect(menuSource.contains("hasPendingChanges: model.hasPendingClaudeCodeChanges"))
        #expect(menuSource.contains("hasPendingChanges: model.hasPendingCodexChanges"))
        #expect(menuSource.contains("hasPendingChanges: model.hasPendingOpenCodeChanges"))
        #expect(!menuSource.contains("requests this session"))
        #expect(menuSource.contains("onToggle: onToggleClaude"))
        #expect(menuSource.contains("onToggle: onToggleClaudeCode"))
        #expect(menuSource.contains("onToggle: onToggleCodex"))
        #expect(menuSource.contains("onToggle: onToggleOpenCode"))
        #expect(menuSource.contains("connected: model.openCodeSwitchOn"))
        #expect(menuSource.contains("model.openCodeStatus == .recoveryUnavailable"))
        #expect(menuSource.contains("model.canPerformOpenCodePrimaryAction"))
        #expect(menuSource.contains("height: StatusMenuLayout.applicationBlockHeight"))
        #expect(controllerSource.contains("height: StatusMenuLayout.applicationBlockHeight"))
        #expect(controllerSource.contains("onToggleOpenCode"))
    }

    @Test("Status menu uses the approved compact application metrics")
    func compactApplicationMetrics() {
        #expect(StatusMenuLayout.width == 320)
        #expect(StatusMenuLayout.applicationRowHeight == 40)
        #expect(StatusMenuLayout.applicationBlockHeight == 188)
        #expect(StatusMenuLayout.iconSize == 20)
        #expect(StatusMenuLayout.titleFontSize == 12)
        #expect(StatusMenuLayout.counterFontSize == 11)
    }

    @Test("Custom model menu copy handles singular and plural counts")
    func customModelCountCopy() {
        #expect(
            [0, 1, 2].map(StatusMenuCopy.customModelCount) == [
                "0 custom models",
                "1 custom model",
                "2 custom models",
            ]
        )
    }

    @Test("All application rows form one uninterrupted status block")
    func uninterruptedApplicationBlock() throws {
        let source = try menuStatusSource()

        #expect(!source.contains("Divider()"))
        #expect(source.contains("StatusMenuLayout.applicationBlockHeight"))
    }

    @Test("LobeHub's Claude Code mark identifies the menu app; settings headings remain text-only")
    func claudeCodeIcon() throws {
        let menuSource = try source(named: "MenuBar/MenuStatusView.swift")
        let settingsSource = try source(named: "Settings/Clients/ClaudeCode/ClaudeCodeSettingsView.swift")
        let iconSource = try source(named: "Components/BrandIcons/ClaudeCodeIcon.swift")

        #expect(menuSource.contains("ClaudeCodeIcon()"))
        #expect(!settingsSource.contains("ClaudeCodeIcon()"))
        #expect(iconSource.contains("https://lobehub.com/icons/claudecode"))
        #expect(iconSource.contains("https://github.com/lobehub/lobe-icons/blob/"))
        #expect(iconSource.contains("4aaf4ee1fb2678a7f989ea570f0f6ce14a9abf75"))
        #expect(iconSource.contains("src/ClaudeCode/components/Color.tsx"))
        #expect(iconSource.contains("red: 217.0 / 255.0"))
        #expect(iconSource.contains("green: 119.0 / 255.0"))
        #expect(iconSource.contains("blue: 87.0 / 255.0"))
        #expect(iconSource.contains("FillStyle(eoFill: true)"))
        #expect(!iconSource.contains("/Users/"))
    }

    @Test("LobeHub's OpenCode mark is used in the menu and settings navigation")
    func openCodeIcon() throws {
        let menuSource = try source(named: "MenuBar/MenuStatusView.swift")
        let settingsSource = try source(named: "Settings/Root/SettingsChrome.swift")

        #expect(menuSource.contains("OpenCodeIcon()"))
        #expect(settingsSource.contains("OpenCodeIcon()"))
        #expect(menuSource.contains("\"Applies to new terminal sessions\""))
    }

    @Test("Claude Code menu confirmations never claim to control a terminal process")
    func claudeCodeConfirmationCopy() throws {
        let source = try source(named: "Application/Lifecycle/LittleSwitchApplicationDelegate.swift")

        #expect(source.contains("Configure new Claude Code sessions to use LittleSwitch?"))
        #expect(source.contains("Restore the previous user-level Claude Code settings?"))
        #expect(!source.localizedCaseInsensitiveContains("quit Claude Code"))
        #expect(!source.localizedCaseInsensitiveContains("restart Claude Code"))
    }

    @Test("OpenCode connects directly while restore confirmation remains process neutral")
    func openCodeWiringAndConfirmationCopy() throws {
        let delegate = try [
            "Application/Lifecycle/LittleSwitchApplicationDelegate.swift",
            "Features/Clients/OpenCode/LittleSwitchApplicationDelegateOpenCode.swift",
        ].map { try source(named: $0) }.joined()
        let controller = try source(named: "MenuBar/StatusItemVisibilityRecovery.swift")
        let settings = try source(named: "Settings/Root/SettingsView.swift")

        #expect(delegate.contains("onToggleOpenCode"))
        #expect(delegate.contains("onOpenCodeDefault"))
        #expect(delegate.contains("onConnectOpenCode"))
        #expect(delegate.contains("onApplyOpenCode"))
        #expect(delegate.contains("onRestoreOpenCode"))
        #expect(controller.contains("onToggleOpenCode"))
        #expect(settings.contains("onOpenCodeDefault"))
        #expect(settings.contains("onConnectOpenCode"))
        #expect(settings.contains("onApplyOpenCode"))
        #expect(settings.contains("onRestoreOpenCode"))
        #expect(!delegate.contains("Configure new OpenCode sessions to use LittleSwitch?"))
        #expect(delegate.contains("Restore the previous user-level OpenCode settings?"))
        #expect(delegate.contains("try await $0.connectOpenCode()"))
        #expect(delegate.contains("try await $0.applyOpenCode()"))
        #expect(delegate.contains("try await $0.restoreOpenCodeSettings()"))
        #expect(!delegate.localizedCaseInsensitiveContains("launch OpenCode"))
        #expect(!delegate.localizedCaseInsensitiveContains("quit OpenCode"))
        #expect(!delegate.localizedCaseInsensitiveContains("restart OpenCode"))
        #expect(!delegate.localizedCaseInsensitiveContains("signal OpenCode"))
    }

    @Test("Command-V routes Paste to the active text responder")
    func pasteCommand() throws {
        let menu = ApplicationMenuFactory.make()
        let editItem = try #require(menu.items.first { $0.title == "Edit" })
        let editMenu = try #require(editItem.submenu)
        let paste = try #require(editMenu.items.first { $0.action == NSSelectorFromString("paste:") })

        #expect(paste.keyEquivalent == "v")
        #expect(paste.keyEquivalentModifierMask == NSEvent.ModifierFlags.command)
        #expect(paste.target == nil)
    }

    private func menuStatusSource() throws -> String {
        try source(named: "MenuBar/MenuStatusView.swift")
    }

    private func source(named filename: String) throws -> String {
        let repository = RepositorySources.root
        return try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/LittleSwitchUI/\(filename)"
            ),
            encoding: .utf8
        )
    }
}
