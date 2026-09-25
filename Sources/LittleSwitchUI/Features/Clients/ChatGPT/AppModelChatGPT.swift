import LittleSwitchCommon

extension AppModel {
    var chatGPTBusy: Bool {
        isBusy || chatGPTStatus == .connecting || chatGPTStatus == .disconnecting
    }

    var canOpenChatGPT: Bool {
        !chatGPTBusy && hasAvailableChatGPTModel && !hasPendingChatGPTChanges
    }

    var hasAvailableChatGPTModel: Bool {
        configuration.chatgpt.resolvedModel(in: providers) != nil
    }

    var canApplyChatGPTSettings: Bool {
        !chatGPTBusy && hasAvailableChatGPTModel && hasPendingChatGPTChanges
    }

    var canConnectDesktopClients: Bool {
        !chatGPTBusy && hasAvailableChatGPTModel && !codexExposedModelOptions.isEmpty
            && !hasUnavailableCodexAutoReviewModel
    }

    /// First-use navigation is presentation state; the coordinator owns the model draft.
    func prepareDesktopConnection() -> Bool {
        guard hasAvailableChatGPTModel else {
            isChoosingChatModelForConnection = true
            selectedSection = .chatGPT
            return false
        }
        return true
    }

    var canDisconnectChatGPT: Bool {
        !chatGPTBusy
            && (configuration.codex.connected || configuration.chatgpt.connected || chatGPTStatus == .needsAttention)
    }

    var chatGPTStatusTitle: String {
        switch chatGPTStatus {
        case .disconnected: L10n.string("Disconnected")
        case .ready: L10n.string("Ready to open")
        case .connected: L10n.string("Connected")
        case .connecting: L10n.string("Opening ChatGPT…")
        case .disconnecting: L10n.string("Disconnecting…")
        case .needsAttention: L10n.string("Needs attention")
        }
    }
}
