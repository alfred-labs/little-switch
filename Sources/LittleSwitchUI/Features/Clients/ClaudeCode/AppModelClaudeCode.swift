import LittleSwitchCommon
import LittleSwitchCore

extension AppModel {
    public enum ClaudeCodePrimaryAction: Equatable, Sendable {
        case connect
        case apply
        case restore
    }

    public var claudeCodeSwitchOn: Bool {
        switch claudeCodeStatus {
        case .connected, .needsAttention, .recoveryAvailable:
            true
        case .disconnected, .recoveryUnavailable:
            false
        }
    }

    public var canApplyClaudeProducts: Bool {
        hasPendingClaudeMappings || canPerformClaudePrimaryAction
            || canPerformClaudeCodePrimaryAction
    }

    public var claudeCodePrimaryAction: ClaudeCodePrimaryAction {
        switch claudeCodeStatus {
        case .disconnected:
            .connect
        case .connected, .needsAttention:
            .apply
        case .recoveryAvailable, .recoveryUnavailable:
            .restore
        }
    }

    public var claudeCodePrimaryActionTitle: String {
        switch claudeCodePrimaryAction {
        case .connect, .apply:
            L10n.string("Apply")
        case .restore:
            L10n.string("Restore settings")
        }
    }

    public var canPerformClaudeCodePrimaryAction: Bool {
        guard !isBusy else {
            return false
        }
        switch claudeCodePrimaryAction {
        case .connect:
            return !claudeCodeMappedRouteOptions.isEmpty
        case .apply:
            guard !claudeCodeMappedRouteOptions.isEmpty else {
                return false
            }
            return hasPendingClaudeCodeChanges || claudeCodeStatus == .needsAttention
        case .restore:
            return claudeCodeStatus == .recoveryAvailable
        }
    }

    public var claudeCodePrimaryActionAccessibilityHint: String {
        if isBusy {
            return L10n.string("An operation is in progress")
        }
        switch claudeCodePrimaryAction {
        case .connect:
            return claudeCodeMappedRouteOptions.isEmpty
                ? L10n.string("Map at least one Claude model before connecting Claude Code")
                : L10n.string("Configures new Claude Code terminal sessions")
        case .apply:
            guard !claudeCodeMappedRouteOptions.isEmpty else {
                return L10n.string("Map at least one Claude model before applying Claude Code")
            }
            if claudeCodeStatus == .needsAttention {
                return L10n.string("Reapplies LittleSwitch settings for new Claude Code sessions")
            }
            return hasPendingClaudeCodeChanges
                ? L10n.string("Applies pending settings to new Claude Code terminal sessions")
                : L10n.string("No pending settings")
        case .restore:
            return claudeCodeStatus == .recoveryAvailable
                ? L10n.string("Restores the previous user-level Claude Code settings")
                : L10n.string("Recovery data is unavailable")
        }
    }

    public var claudeCodePrimaryActionAccessibilityValue: String {
        switch claudeCodeStatus {
        case .disconnected:
            L10n.string("Claude Code disconnected")
        case .connected:
            if hasPendingClaudeCodeChanges {
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

    public var claudeCodeMappedRouteOptions: [ClaudeRoute] {
        ClaudeRoute.all.filter { claudeCodeMappedRouteIDs.contains($0.id) }
    }

    public var claudeCodeDefaultRouteID: String? {
        let available = claudeCodeMappedRouteOptions.map(\.id)
        guard let defaultModel = configuration.claudeCode.defaultModel else {
            return available.first
        }
        return available.contains(defaultModel) ? defaultModel : available.first
    }

    public var claudeCodeDefaultModelOptions: [ClaudeCodeDefaultModelOption] {
        claudeCodeMappedRouteOptions.flatMap { route -> [ClaudeCodeDefaultModelOption] in
            guard let mapping = configuration.mappings[route.id],
                let provider = configuration.providers.first(
                    where: { $0.id == mapping.providerID }
                ),
                let model = provider.models.first(where: { $0.id == mapping.modelID })
            else {
                return []
            }

            var options = [
                ClaudeCodeDefaultModelOption(
                    routeID: route.id,
                    contextMode: .standard,
                    label: route.displayName
                )
            ]
            if model.supports1MContext {
                options.append(
                    ClaudeCodeDefaultModelOption(
                        routeID: route.id,
                        contextMode: .extended1M,
                        label: L10n.string("\(route.displayName) [1m]")
                    )
                )
            }
            return options
        }
    }

    public var claudeCodeDefaultModelSelection: ClaudeCodeDefaultModelOption? {
        guard let routeID = claudeCodeDefaultRouteID else {
            return claudeCodeDefaultModelOptions.first
        }
        return claudeCodeDefaultModelOptions.first {
            $0.routeID == routeID
                && $0.contextMode == configuration.claudeCode.contextMode
        } ?? claudeCodeDefaultModelOptions.first {
            $0.routeID == routeID && $0.contextMode == .standard
        } ?? claudeCodeDefaultModelOptions.first
    }

}
