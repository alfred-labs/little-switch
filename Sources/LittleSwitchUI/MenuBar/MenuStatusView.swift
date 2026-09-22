import LittleSwitchCommon
import SwiftUI

public struct MenuStatusView: View {
    @Bindable private var model: AppModel
    private let onToggleClaude: @MainActor () -> Void
    private let onToggleClaudeCode: @MainActor () -> Void
    private let onToggleCodex: @MainActor () -> Void
    private let onToggleOpenCode: @MainActor () -> Void
    private let onOpenApplication: @MainActor (DesktopApplication) -> Void

    init(
        model: AppModel,
        onToggleClaude: @escaping @MainActor () -> Void,
        onToggleClaudeCode: @escaping @MainActor () -> Void,
        onToggleCodex: @escaping @MainActor () -> Void,
        onToggleOpenCode: @escaping @MainActor () -> Void,
        onOpenApplication: @escaping @MainActor (DesktopApplication) -> Void = { _ in }
    ) {
        self.model = model
        self.onToggleClaude = onToggleClaude
        self.onToggleClaudeCode = onToggleClaudeCode
        self.onToggleCodex = onToggleCodex
        self.onToggleOpenCode = onToggleOpenCode
        self.onOpenApplication = onOpenApplication
    }

    public var body: some View {
        VStack(spacing: StatusMenuLayout.applicationRowSpacing) {
            ApplicationStatusRow(
                name: L10n.string("Claude Desktop"),
                icon: .claudeDesktop,
                detail: StatusMenuCopy.detail(
                    StatusMenuCopy.customModelCount(model.claudeCustomModelCount),
                    hasPendingChanges: model.hasPendingClaudeMappings
                ),
                connected: model.connected,
                disabled: model.isBusy,
                access: model.desktopApplications.claude,
                launching: model.launchingApplications.contains(.claude),
                launchDisabled: model.isBusy,
                onToggle: onToggleClaude
            ) { onOpenApplication(.claude) }
            ApplicationStatusRow(
                name: L10n.string("Claude Code"),
                icon: .claudeCode,
                detail: StatusMenuCopy.detail(
                    L10n.string("Applies to new terminal sessions"),
                    hasPendingChanges: model.hasPendingClaudeCodeChanges
                ),
                connected: model.claudeCodeSwitchOn,
                disabled: model.isBusy || model.claudeCodeStatus == .recoveryUnavailable,
                onToggle: onToggleClaudeCode
            )
            ApplicationStatusRow(
                name: L10n.string("Codex"),
                icon: .codex,
                detail: StatusMenuCopy.detail(
                    StatusMenuCopy.customModelCount(model.codexCustomModelCount),
                    hasPendingChanges: model.hasPendingCodexChanges
                ),
                connected: model.codexConnected,
                disabled: model.isBusy,
                access: model.desktopApplications.codex,
                launching: model.launchingApplications.contains(.codex),
                launchDisabled: model.isBusy,
                onToggle: onToggleCodex
            ) { onOpenApplication(.codex) }
            ApplicationStatusRow(
                name: L10n.string("OpenCode"),
                icon: .openCode,
                detail: StatusMenuCopy.detail(
                    L10n.string("Applies to new terminal sessions"),
                    hasPendingChanges: model.hasPendingOpenCodeChanges
                ),
                connected: model.openCodeSwitchOn,
                disabled: model.isBusy
                    || model.openCodeStatus == .recoveryUnavailable
                    || (!model.openCodeSwitchOn
                        && !model.canPerformOpenCodePrimaryAction),
                access: model.desktopApplications.openCode,
                launching: model.launchingApplications.contains(.openCode),
                launchDisabled: model.isBusy,
                onToggle: onToggleOpenCode
            ) { onOpenApplication(.openCode) }
        }
        .padding(.vertical, StatusMenuLayout.applicationBlockVerticalPadding)
        .frame(
            width: StatusMenuLayout.width,
            height: StatusMenuLayout.applicationBlockHeight
        )
        .accessibilityElement(children: .contain)
    }
}

/// Every row shows its bundled brand mark — the app never borrows icons
/// from the applications it switches, so the marks are present whether or
/// not the counterpart app is installed.
enum ApplicationStatusIcon {
    case claudeDesktop
    case claudeCode
    case codex
    case openCode

    @ViewBuilder
    var mark: some View {
        switch self {
        case .claudeDesktop:
            ClaudeIcon()
        case .claudeCode:
            ClaudeCodeIcon()
        case .codex:
            CodexIcon()
        case .openCode:
            OpenCodeIcon()
        }
    }
}
