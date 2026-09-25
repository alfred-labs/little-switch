import LittleSwitchCommon

extension AppModel {
    var codexConnected: Bool {
        configuration.codex.connected
    }

    var codexPrimaryAction: CodexPrimaryAction {
        codexConnected ? .apply : .connect
    }

    var codexPrimaryActionTitle: String {
        L10n.string("Apply")
    }

    var canPerformCodexPrimaryAction: Bool {
        guard !codexExposedModelOptions.isEmpty, !hasUnavailableCodexAutoReviewModel, !isBusy else {
            return false
        }
        switch codexPrimaryAction {
        case .connect:
            return true
        case .apply:
            return hasPendingCodexChanges
        }
    }

    var codexPrimaryActionAccessibilityHint: String {
        if hasUnavailableCodexAutoReviewModel {
            return L10n.string("Choose an available approval review model before applying changes")
        }
        if codexExposedModelOptions.isEmpty {
            return codexConnected
                ? L10n.string("Expose at least one available model before applying changes")
                : L10n.string("Expose at least one available model before connecting Codex")
        }
        if isBusy {
            return L10n.string("An operation is in progress")
        }
        switch codexPrimaryAction {
        case .connect:
            return L10n.string("Connects Codex to LittleSwitch")
        case .apply:
            return hasPendingCodexChanges
                ? L10n.string("Applies pending settings")
                : L10n.string("No pending settings")
        }
    }

    var codexPrimaryActionAccessibilityValue: String {
        guard codexConnected else {
            return L10n.string("Codex disconnected")
        }
        return hasPendingCodexChanges ? L10n.string("Changes pending") : L10n.string("No pending changes")
    }
}
