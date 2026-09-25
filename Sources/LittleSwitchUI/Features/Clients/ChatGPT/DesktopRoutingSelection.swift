import LittleSwitchCommon
import LittleSwitchCore

/// The desktop reads its catalog while opening, before durable intent can be
/// committed. Background provider updates must preserve that prepared selection.
struct DesktopRoutingSelection: Sendable {
    let codex: CodexConfiguration
    let chatgpt: ChatGPTConfiguration

    init(configuration: AppConfiguration) {
        codex = configuration.codex
        chatgpt = configuration.chatgpt
    }
}

extension ApplicationCoordinator {
    func applyingDesktopRouting(to configuration: AppConfiguration) -> AppConfiguration {
        var routing = configuration
        if let desktopRoutingSelection {
            routing.codex = desktopRoutingSelection.codex
            routing.chatgpt = desktopRoutingSelection.chatgpt
        }
        return routing
    }

    func validateDesktopSettings(unchangedSince previous: AppConfiguration) throws {
        guard retainingCurrentImageObservations(in: previous) == configuration else {
            throw ChatGPTConnectionError.settingsChanged
        }
    }
}
