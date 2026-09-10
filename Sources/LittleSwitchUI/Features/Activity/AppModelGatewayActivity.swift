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
            names.append("Web search")
        }
        if monitoringDraft != nil {
            names.append("Monitoring")
        }
        return names
    }

    public var hasPendingChanges: Bool {
        !pendingChangeNames.isEmpty
    }

    /// Nil when nothing would be lost, so callers can skip the question.
    public var pendingChangesWarning: String? {
        let names = pendingChangeNames
        guard !names.isEmpty else {
            return nil
        }
        return "Unapplied changes for \(AppModel.list(names)) will be discarded."
    }

    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0:
            return ""
        case 1:
            return names[0]
        case 2:
            return "\(names[0]) and \(names[1])"
        default:
            return "\(names.dropLast().joined(separator: ", ")), and \(names[names.count - 1])"
        }
    }
}
