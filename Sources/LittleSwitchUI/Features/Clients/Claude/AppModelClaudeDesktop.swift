import LittleSwitchCommon

extension AppModel {
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
        case nil:
            return L10n.string("Model routing edits wait for Apply")
        }
    }

    private var hasValidRouting: Bool {
        RoutingSnapshot(
            generation: 0,
            providers: configuration.providers,
            mappings: configuration.mappings
        ).hasValidMapping
    }
}
