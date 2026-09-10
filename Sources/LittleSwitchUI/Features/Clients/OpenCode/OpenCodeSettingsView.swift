import LittleSwitchCore
import SwiftUI

struct OpenCodeSettingsView: View {
    @Bindable var model: AppModel
    let onDefault: @MainActor (ModelMapping?) async -> Void
    let onConnect: @MainActor () async -> Void
    let onApply: @MainActor () async -> Void
    let onRestore: @MainActor () async -> Void

    var body: some View {
        SettingsPage {
            routingSection
            SettingsSection("Available models") {
                SettingsCard {
                    HStack {
                        Text("\(model.codexExposedModelOptions.count) enabled")
                            .monospacedDigit()
                        Spacer(minLength: 12)
                        Button("Manage in Codex…") { model.selectedSection = .codex }
                    }
                    .settingsRow()
                }
                Text("The model catalog is shared with Codex.")
                    .settingsSupportingText()
            }
            SettingsSection("Terminal") {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Changes apply to new OpenCode terminal sessions.")
                        Text("Project settings can override this default.")
                            .settingsSupportingText()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .toolbar {
            SettingsToolbarActions {
                if showsCodexGateNotice {
                    Label("Apply Codex first", systemImage: "arrow.up.forward.app")
                        .font(SettingsLayout.Typography.toolbarLabel)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .help("Apply Codex changes first, then apply OpenCode settings.")
                } else if model.hasPendingOpenCodeChanges {
                    SettingsPendingNotice()
                } else {
                    SettingsConnectionStatus(connected: model.openCodeStatus == .connected)
                }
                Button(
                    model.isBusy ? "Applying…" : model.openCodePrimaryActionTitle,
                    systemImage: model.openCodePrimaryAction == .restore ? "arrow.uturn.backward" : "checkmark"
                ) {
                    let action = model.openCodePrimaryAction
                    Task {
                        switch action {
                        case .connect: await onConnect()
                        case .apply: await onApply()
                        case .restore: await onRestore()
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canPerformOpenCodePrimaryAction)
                .accessibilityHint(model.openCodePrimaryActionAccessibilityHint)
                .accessibilityValue(model.openCodePrimaryActionAccessibilityValue)
            }
        }
    }

    private var routingSection: some View {
        SettingsSection("Model routing", subtitle: "For OpenCode terminal sessions.") {
            SettingsCard {
                Grid(horizontalSpacing: 14, verticalSpacing: 0) {
                    SettingsMappingRow("Default model") {
                        Picker(
                            "Default model",
                            selection: Binding<String?>(
                                get: { model.openCodeDefaultOptionID },
                                set: { optionID in
                                    let mapping = model.mapping(for: optionID)
                                    Task { await onDefault(mapping) }
                                }
                            )
                        ) {
                            ForEach(model.openCodeDefaultModelOptions) { option in
                                Text(option.label).tag(Optional(option.id))
                            }
                        }
                        .disabled(model.isBusy || model.openCodeDefaultModelOptions.isEmpty)
                    }
                }
            }
            statusNotice
            if model.openCodeDefaultModelOptions.isEmpty {
                notice("Enable a model in Codex before connecting OpenCode.", systemImage: "info.circle")
            }
        }
    }

    private var showsCodexGateNotice: Bool {
        model.hasPendingCodexChanges && model.openCodePrimaryAction != .restore
    }

    @ViewBuilder
    private var statusNotice: some View {
        switch model.openCodeStatus {
        case .disconnected:
            EmptyView()
        case .connected:
            EmptyView()
        case .needsAttention:
            notice(
                "OpenCode settings changed outside LittleSwitch. Apply them again or restore the previous settings.",
                systemImage: "exclamationmark.triangle"
            )
        case .recoveryAvailable:
            notice(
                "Previous user-level settings can be restored.",
                systemImage: "clock.arrow.circlepath"
            )
        case .recoveryUnavailable:
            notice(
                "Recovery data is unavailable.",
                systemImage: "exclamationmark.octagon"
            )
        }
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .settingsSupportingText()
    }
}
