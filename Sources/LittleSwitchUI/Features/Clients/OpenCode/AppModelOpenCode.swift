import LittleSwitchCore

extension AppModel {
    public enum OpenCodePrimaryAction: Equatable, Sendable {
        case connect
        case apply
        case restore
    }

    public var openCodeSwitchOn: Bool {
        switch openCodeStatus {
        case .connected, .needsAttention, .recoveryAvailable:
            true
        case .disconnected, .recoveryUnavailable:
            false
        }
    }

    public var openCodePrimaryAction: OpenCodePrimaryAction {
        switch openCodeStatus {
        case .disconnected:
            .connect
        case .connected, .needsAttention:
            .apply
        case .recoveryAvailable, .recoveryUnavailable:
            .restore
        }
    }

    public var openCodePrimaryActionTitle: String {
        switch openCodePrimaryAction {
        case .connect, .apply:
            L10n.string("Apply")
        case .restore:
            L10n.string("Restore settings")
        }
    }

    public var canPerformOpenCodePrimaryAction: Bool {
        guard !isBusy else {
            return false
        }
        switch openCodePrimaryAction {
        case .connect:
            return !hasPendingCodexChanges && !openCodeDefaultModelOptions.isEmpty
        case .apply:
            guard !hasPendingCodexChanges, !openCodeDefaultModelOptions.isEmpty else {
                return false
            }
            return hasPendingOpenCodeChanges || openCodeStatus == .needsAttention
        case .restore:
            return openCodeStatus == .recoveryAvailable
        }
    }

    public var openCodePrimaryActionAccessibilityHint: String {
        if isBusy {
            return L10n.string("An operation is in progress")
        }
        switch openCodePrimaryAction {
        case .connect:
            if hasPendingCodexChanges {
                return L10n.string("Apply Codex changes first")
            }
            return openCodeDefaultModelOptions.isEmpty
                ? L10n.string("Expose at least one model in Codex before connecting OpenCode")
                : L10n.string("Configures OpenCode to use LittleSwitch")
        case .apply:
            if hasPendingCodexChanges {
                return L10n.string("Apply Codex changes first")
            }
            guard !openCodeDefaultModelOptions.isEmpty else {
                return L10n.string("Expose at least one model in Codex before applying OpenCode")
            }
            if openCodeStatus == .needsAttention {
                return L10n.string("Reapplies LittleSwitch settings to OpenCode")
            }
            return hasPendingOpenCodeChanges
                ? L10n.string("Applies pending settings to OpenCode")
                : L10n.string("No pending settings")
        case .restore:
            return openCodeStatus == .recoveryAvailable
                ? L10n.string("Restores the previous user-level OpenCode settings")
                : L10n.string("Recovery data is unavailable")
        }
    }

    public var openCodePrimaryActionAccessibilityValue: String {
        switch openCodeStatus {
        case .disconnected:
            L10n.string("OpenCode disconnected")
        case .connected:
            if hasPendingOpenCodeChanges {
                L10n.string("Changes pending")
            } else {
                L10n.string("No pending changes")
            }
        case .needsAttention:
            L10n.string("Needs attention")
        case .recoveryAvailable:
            L10n.string("Recovery available")
        case .recoveryUnavailable:
            L10n.string("Recovery unavailable")
        }
    }

    public var openCodeDefaultModelOptions: [ModelOption] {
        codexExposedModelOptions
    }

    public var openCodeDefaultOptionID: String? {
        let available = openCodeDefaultModelOptions
        if let defaultModel = configuration.openCode.defaultModel {
            if let option = available.first(where: { $0.mapping == defaultModel }) {
                return option.id
            }
        }
        return available.first?.id
    }
}
