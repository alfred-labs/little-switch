import LittleSwitchCommon
import SwiftUI

struct ChatGPTSettingsView: View {
    @Bindable var model: AppModel
    let onModel: @MainActor (ModelMapping?) async -> Void
    let onApply: @MainActor () async -> Void
    let onConnect: @MainActor () async -> Void
    let onOpen: @MainActor () async -> Void
    let onDisconnect: @MainActor () async -> Void

    var body: some View {
        SettingsPage {
            SettingsSection(L10n.resource("Model")) {
                SettingsCard {
                    Grid(horizontalSpacing: 14, verticalSpacing: 0) {
                        SettingsMappingRow(L10n.string("ChatGPT")) {
                            modelPicker
                        }
                    }
                }
                Text(L10n.resource("This choice does not change Codex models."))
                    .settingsSupportingText()
                if model.hasPendingChatGPTChanges && model.configuration.chatgpt.connected {
                    Text(L10n.resource("Applying will relaunch ChatGPT."))
                        .settingsSupportingText()
                }
                if model.modelOptions.isEmpty {
                    Text(L10n.resource("Add and refresh a provider to make its models available."))
                        .settingsSupportingText()
                    Button(L10n.resource("Add a Provider…")) { model.selectedSection = .providers }
                } else if !model.hasAvailableChatGPTModel {
                    Text(L10n.resource("Choose an available model for Chat before connecting."))
                        .settingsSupportingText()
                }
                if model.isChoosingChatModelForConnection {
                    Text(L10n.resource("Choose the model for Chat, then connect Codex and ChatGPT together."))
                        .settingsSupportingText()
                }
            }
            SettingsSection(L10n.resource("Connection")) {
                SettingsCard {
                    LabeledContent {
                        Text(L10n.resource("Codex"))
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(L10n.resource("Enabled with"))
                    }
                    .settingsRow()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.resource("Enabled with"))
                    .accessibilityValue(L10n.resource("Codex"))
                    LabeledContent {
                        Text(L10n.resource("On this Mac"))
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(L10n.resource("Chat history"))
                    }
                    .settingsRow()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.resource("Chat history"))
                    .accessibilityValue(L10n.resource("On this Mac"))
                }
                .accessibilityElement(children: .contain)
                Text(L10n.resource("Native ChatGPT models remain available."))
                    .settingsSupportingText()
                if model.chatGPTStatus == .needsAttention {
                    Text(L10n.resource("Reload the desktop app to recover the connection, or disconnect both apps."))
                        .settingsSupportingText()
                }
            }
        }
        .toolbar {
            SettingsToolbarActions {
                if model.hasPendingChatGPTChanges {
                    SettingsPendingNotice()
                } else {
                    Text(model.chatGPTStatusTitle)
                        .font(SettingsLayout.Typography.toolbarLabel)
                        .foregroundStyle(.secondary)
                }
                if model.isChoosingChatModelForConnection {
                    Button(L10n.resource("Cancel")) { model.isChoosingChatModelForConnection = false }
                        .disabled(model.chatGPTBusy)
                    Button(L10n.resource("Connect Codex and ChatGPT"), systemImage: "checkmark") {
                        Task { await onConnect() }
                    }
                    .disabled(!model.canConnectDesktopClients)
                    .keyboardShortcut("s", modifiers: .command)
                } else {
                    if model.canDisconnectChatGPT || model.configuration.chatgpt.connected {
                        Button(L10n.resource("Disconnect")) { Task { await onDisconnect() } }
                            .disabled(!model.canDisconnectChatGPT)
                            .accessibilityLabel(L10n.resource("Disconnect Codex and ChatGPT"))
                    }
                    if model.configuration.chatgpt.connected {
                        Button(L10n.resource("Reload"), systemImage: "arrow.clockwise") { Task { await onOpen() } }
                            .disabled(!model.canOpenChatGPT || !model.canConnectDesktopClients)
                            .accessibilityLabel(L10n.resource("Reload Codex and ChatGPT"))
                    }
                    Button(L10n.resource("Apply"), systemImage: "checkmark") { Task { await onApply() } }
                        .disabled(!model.canApplyChatGPTSettings)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
    }

    private var modelPicker: some View {
        Picker(
            L10n.resource("Model for Chat"),
            selection: Binding<ModelMapping?>(
                get: { model.configuration.chatgpt.model },
                set: { mapping in Task { await onModel(mapping) } }
            )
        ) {
            if model.configuration.chatgpt.model == nil {
                Text(L10n.resource("Choose a model…")).tag(nil as ModelMapping?)
            }
            ForEach(model.modelOptions) { option in
                Text(option.label).tag(Optional(option.mapping))
            }
            if let mapping = model.configuration.chatgpt.model, !model.hasAvailableChatGPTModel {
                Text(L10n.resource("Unavailable: \(mapping.modelID)")).tag(Optional(mapping))
            }
        }
        .disabled(model.chatGPTBusy || model.modelOptions.isEmpty)
    }
}
