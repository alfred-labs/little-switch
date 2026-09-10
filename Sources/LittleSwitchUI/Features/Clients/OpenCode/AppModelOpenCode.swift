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
            "Apply"
        case .restore:
            "Restore settings"
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
            return "An operation is in progress"
        }
        switch openCodePrimaryAction {
        case .connect:
            if hasPendingCodexChanges {
                return "Apply Codex changes first"
            }
            return openCodeDefaultModelOptions.isEmpty
                ? "Expose at least one model in Codex before connecting OpenCode"
                : "Configures OpenCode to use LittleSwitch"
        case .apply:
            if hasPendingCodexChanges {
                return "Apply Codex changes first"
            }
            guard !openCodeDefaultModelOptions.isEmpty else {
                return "Expose at least one model in Codex before applying OpenCode"
            }
            if openCodeStatus == .needsAttention {
                return "Reapplies LittleSwitch settings to OpenCode"
            }
            return hasPendingOpenCodeChanges
                ? "Applies pending settings to OpenCode"
                : "No pending settings"
        case .restore:
            return openCodeStatus == .recoveryAvailable
                ? "Restores the previous user-level OpenCode settings"
                : "Recovery data is unavailable"
        }
    }

    public var openCodePrimaryActionAccessibilityValue: String {
        switch openCodeStatus {
        case .disconnected:
            "OpenCode disconnected"
        case .connected:
            hasPendingOpenCodeChanges ? "Changes pending" : "No pending changes"
        case .needsAttention:
            "Needs attention"
        case .recoveryAvailable:
            "Recovery available"
        case .recoveryUnavailable:
            "Recovery unavailable"
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
