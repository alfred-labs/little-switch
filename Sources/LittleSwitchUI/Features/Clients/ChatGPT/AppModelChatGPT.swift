import LittleSwitchCommon

extension AppModel {
    var chatGPTBusy: Bool {
        isBusy || chatGPTStatus == .connecting || chatGPTStatus == .disconnecting
    }

    var canOpenChatGPT: Bool {
        !chatGPTBusy && !codexExposedModelOptions.isEmpty && !hasPendingCodexChanges
    }

    var canDisconnectChatGPT: Bool {
        !chatGPTBusy && (configuration.chatgpt.connected || chatGPTStatus == .needsAttention)
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
