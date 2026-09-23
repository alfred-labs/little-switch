import LittleSwitchCommon

extension AppModel {
    var claudePrimaryAction: ClaudePrimaryAction? {
        guard connected else { return .connect }
        // Routing changes reach the gateway immediately after Apply; a changed
        // Desktop model list waits for its separate, explicit profile action.
        return hasPendingClaudeDesktopChanges ? .apply : nil
    }

    var claudePrimaryActionTitle: String {
        L10n.string("Apply")
    }

    var claudePrimaryActionAccessibilityValue: String {
        guard connected else {
            return L10n.string("Claude disconnected")
        }
        if hasPendingClaudeDesktopChanges {
            return L10n.string("Pending in Claude")
        }
        return hasPendingClaudeMappings ? L10n.string("Changes pending") : L10n.string("No pending changes")
    }

    var canPerformClaudePrimaryAction: Bool {
        guard hasValidRouting, !isBusy, desktopApplications.claude != .organizationManaged else {
            return false
        }
        return claudePrimaryAction != nil
    }

    var claudePrimaryActionAccessibilityHint: String {
        if desktopApplications.claude == .organizationManaged {
            return L10n.string("Your organization manages Claude Desktop. LittleSwitch cannot open or connect it.")
        }
        if !hasValidRouting {
            return connected
                ? L10n.string("Choose at least one available model to restore live routing")
                : L10n.string("Assign at least one available model before applying settings")
        }
        if isBusy {
            return L10n.string("An operation is in progress")
        }
        switch claudePrimaryAction {
        case .connect:
            return L10n.string("Applies LittleSwitch settings to Claude Desktop")
        case .apply:
            return L10n.string("Updates the model list in Claude Desktop and restarts it if it is running")
        case nil:
            return L10n.string("Model routing edits wait for Apply")
        }
    }

    var claudeProductsApplyAccessibilityHint: String {
        if canPerformClaudePrimaryAction, claudePrimaryAction == .apply {
            return claudePrimaryActionAccessibilityHint
        }
        return L10n.string("Applies pending settings and connects Claude apps")
    }

    private var hasValidRouting: Bool {
        RoutingSnapshot(
            generation: 0,
            providers: configuration.providers,
            mappings: configuration.mappings
        ).hasValidMapping
    }
}
