import LittleSwitchCommon
import SwiftUI

struct ChatGPTSettingsView: View {
    @Bindable var model: AppModel
    let onOpen: @MainActor () async -> Void
    let onDisconnect: @MainActor () async -> Void

    var body: some View {
        SettingsPage {
            SettingsSection(L10n.resource("Text conversations")) {
                SettingsCard {
                    LabeledContent {
                        Text(model.chatGPTStatusTitle)
                    } label: {
                        Text(L10n.resource("Connection"))
                    }
                    .settingsRow()
                    .accessibilityLabel(L10n.resource("ChatGPT connection"))
                    .accessibilityValue(model.chatGPTStatusTitle)
                }
                Text(
                    L10n.resource(
                        "Chat with your enabled provider models in the ChatGPT desktop app. Conversations are saved locally on this Mac."
                    )
                )
                .settingsSupportingText()
            }
            SettingsSection(L10n.resource("Available models")) {
                SettingsCard {
                    HStack {
                        Text(L10n.resource("\(model.codexExposedModelOptions.count) enabled"))
                            .monospacedDigit()
                        Spacer(minLength: 12)
                        Button(L10n.resource("Manage in Codex…")) { model.selectedSection = .codex }
                    }
                    .settingsRow()
                }
                Text(L10n.resource("The model catalog is shared with Codex. Native models remain available."))
                    .settingsSupportingText()
                if model.hasPendingCodexChanges {
                    Text(L10n.resource("Apply Codex changes before opening ChatGPT."))
                        .settingsSupportingText()
                } else if model.codexExposedModelOptions.isEmpty {
                    Text(L10n.resource("Enable a model in Codex before connecting ChatGPT."))
                        .settingsSupportingText()
                }
            }
            SettingsSection(L10n.resource("Desktop app")) {
                Text(
                    L10n.resource(
                        "Open ChatGPT from LittleSwitch to connect. Connecting or reloading reopens the desktop app shared with Codex."
                    )
                )
                .settingsSupportingText()
                Text(L10n.resource("A fresh launch outside LittleSwitch uses the normal connection."))
                    .settingsSupportingText()
                Text(
                    L10n.resource(
                        "After changing the shared model selection, reload ChatGPT to refresh its model list."
                    )
                )
                .settingsSupportingText()
                if model.chatGPTStatus == .needsAttention {
                    Label(
                        L10n.resource(
                            "Open ChatGPT again to recover the connection, or disconnect to restore its normal launch."
                        ),
                        systemImage: "exclamationmark.triangle"
                    )
                    .settingsSupportingText()
                }
            }
        }
        .toolbar {
            SettingsToolbarActions {
                Text(model.chatGPTStatusTitle)
                    .font(SettingsLayout.Typography.toolbarLabel)
                    .foregroundStyle(.secondary)
                if model.canDisconnectChatGPT || model.configuration.chatgpt.connected {
                    Button(L10n.resource("Disconnect")) { Task { await onDisconnect() } }
                        .disabled(!model.canDisconnectChatGPT)
                        .accessibilityLabel(L10n.resource("Disconnect ChatGPT"))
                }
                Button(
                    model.configuration.chatgpt.connected
                        ? L10n.string("Open / Reload ChatGPT") : L10n.string("Connect ChatGPT"),
                    systemImage: "arrow.clockwise"
                ) { Task { await onOpen() } }
                .disabled(!model.canOpenChatGPT)
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityHint(L10n.resource("Reopens ChatGPT from LittleSwitch with the enabled models"))
            }
        }
    }
}
