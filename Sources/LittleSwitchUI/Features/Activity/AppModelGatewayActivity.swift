import Foundation
import LittleSwitchCore

/// Gateway activity and usage projection for the status menu. Split from
/// `AppModel` so the presentation state stays reviewable next to the request
/// queue it describes.
@MainActor
extension AppModel {
    public var gatewayActivityPresentation: GatewayActivityPresentation {
        GatewayActivityPresentation(
            activity: gatewayActivity,
            providers: configuration.providers,
            usage: gatewayUsage,
            webSearchProvider: configuration.webSearch.provider
        )
    }
}

@MainActor
extension AppModel {
    /// Applications and panes holding changes that exist only in a draft.
    /// Disconnecting or quitting throws these away, so both paths ask first.
    public var pendingChangeNames: [String] {
        var names: [String] = []
        if hasPendingClaudeMappings {
            names.append("Claude")
        }
        if hasPendingClaudeCodeChanges {
            names.append("Claude Code")
        }
        if hasPendingCodexChanges {
            names.append("Codex")
        }
        if hasPendingOpenCodeChanges {
            names.append("OpenCode")
        }
        if webSearchDraft != nil {
            names.append(L10n.string("Web search"))
        }
        if monitoringDraft != nil {
            names.append(L10n.string("Monitoring"))
        }
        return names
    }

    public var hasPendingChanges: Bool {
        hasPendingClaudeDesktopChanges || !pendingChangeNames.isEmpty
    }

    /// Saved catalog changes still need an explicit Desktop Apply. Keep that
    /// notice separate from drafts that disconnecting or quitting discards.
    public var pendingChangesWarning: String? {
        let names = pendingChangeNames
        var warnings: [String] = []
        if !names.isEmpty {
            warnings.append(L10n.string("Unapplied changes for \(AppModel.list(names)) will be discarded."))
        }
        if hasPendingClaudeDesktopChanges {
            warnings.append(L10n.string("The model list still needs to be applied in Claude Desktop."))
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: " ")
    }

    static func list(_ names: [String]) -> String {
        ListFormatter.localizedString(byJoining: names)
    }
}
