import SwiftUI

public struct MenuStatusView: View {
    @Bindable private var model: AppModel
    private let onToggleClaude: @MainActor () -> Void
    private let onToggleClaudeCode: @MainActor () -> Void
    private let onToggleCodex: @MainActor () -> Void
    private let onToggleOpenCode: @MainActor () -> Void

    init(
        model: AppModel,
        onToggleClaude: @escaping @MainActor () -> Void,
        onToggleClaudeCode: @escaping @MainActor () -> Void,
        onToggleCodex: @escaping @MainActor () -> Void,
        onToggleOpenCode: @escaping @MainActor () -> Void
    ) {
        self.model = model
        self.onToggleClaude = onToggleClaude
        self.onToggleClaudeCode = onToggleClaudeCode
        self.onToggleCodex = onToggleCodex
        self.onToggleOpenCode = onToggleOpenCode
    }

    public var body: some View {
        VStack(spacing: StatusMenuLayout.applicationRowSpacing) {
            ApplicationStatusRow(
                name: "Claude Desktop",
                icon: .claudeDesktop,
                detail: StatusMenuCopy.detail(
                    StatusMenuCopy.customModelCount(model.claudeCustomModelCount),
                    hasPendingChanges: model.hasPendingClaudeMappings
                ),
                connected: model.connected,
                disabled: model.isBusy,
                onToggle: onToggleClaude
            )
            ApplicationStatusRow(
                name: "Claude Code",
                icon: .claudeCode,
                detail: StatusMenuCopy.detail(
                    "Applies to new terminal sessions",
                    hasPendingChanges: model.hasPendingClaudeCodeChanges
                ),
                connected: model.claudeCodeSwitchOn,
                disabled: model.isBusy || model.claudeCodeStatus == .recoveryUnavailable,
                onToggle: onToggleClaudeCode
            )
            ApplicationStatusRow(
                name: "Codex",
                icon: .codex,
                detail: StatusMenuCopy.detail(
                    StatusMenuCopy.customModelCount(model.codexCustomModelCount),
                    hasPendingChanges: model.hasPendingCodexChanges
                ),
                connected: model.codexConnected,
                disabled: model.isBusy,
                onToggle: onToggleCodex
            )
            ApplicationStatusRow(
                name: "OpenCode",
                icon: .openCode,
                detail: StatusMenuCopy.detail(
                    "Applies to new terminal sessions",
                    hasPendingChanges: model.hasPendingOpenCodeChanges
                ),
                connected: model.openCodeSwitchOn,
                disabled: model.isBusy
                    || model.openCodeStatus == .recoveryUnavailable
                    || (!model.openCodeSwitchOn
                        && !model.canPerformOpenCodePrimaryAction),
                onToggle: onToggleOpenCode
            )
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
private enum ApplicationStatusIcon {
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

private struct ApplicationStatusRow: View {
    let name: String
    let icon: ApplicationStatusIcon
    let detail: String
    let connected: Bool
    let disabled: Bool
    let onToggle: @MainActor () -> Void

    var body: some View {
        HStack(spacing: StatusMenuLayout.contentSpacing) {
            icon.mark
                .frame(width: StatusMenuLayout.iconSize, height: StatusMenuLayout.iconSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: StatusMenuLayout.titleFontSize, weight: .medium))
                Text(detail)
                    .font(.system(size: StatusMenuLayout.counterFontSize))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle(
                "\(name) connection",
                isOn: Binding(
                    get: { connected },
                    set: { _ in onToggle() }
                )
            )
            .labelsHidden()
            .toggleStyle(StatusMenuSwitchStyle())
            .controlSize(.mini)
            .disabled(disabled)
        }
        .padding(.horizontal, StatusMenuLayout.horizontalPadding)
        .frame(
            width: StatusMenuLayout.width,
            height: StatusMenuLayout.applicationRowHeight
        )
        .accessibilityElement(children: .contain)
    }
}
