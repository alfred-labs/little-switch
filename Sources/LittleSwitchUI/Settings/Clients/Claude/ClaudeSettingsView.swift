import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI

struct ClaudeSettingsView: View {
    @Bindable var model: AppModel
    let onMapping: @MainActor (String, ModelMapping?) async -> Void
    let onAutoMode: @MainActor (Bool) async -> Void
    let onApplyAll:
        @MainActor (
            AppModel.ClaudePrimaryAction?,
            AppModel.ClaudeCodePrimaryAction?
        ) async -> Void
    let onClaudeCodeDefault: @MainActor (String?, ClaudeCodeContextMode) async -> Void

    var body: some View {
        SettingsPage {
            routingSection
            SettingsSection("Desktop") {
                SettingsCard {
                    autoModeRow
                        .padding(.vertical, 6)
                }
            }
            ClaudeCodeSettingsView(model: model, onDefault: onClaudeCodeDefault)
        }
        .toolbar {
            SettingsToolbarActions {
                if model.hasPendingClaudeMappings || model.hasPendingClaudeCodeChanges {
                    SettingsPendingNotice()
                } else {
                    SettingsConnectionStatus(
                        connected: model.connected || model.claudeCodeStatus == .connected,
                        title: connectionTitle
                    )
                }
                Button(model.isBusy ? "Applying…" : "Apply", systemImage: "checkmark") {
                    Task { await applyAllClaudeSettings() }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canApplyClaudeProducts)
                .accessibilityHint("Applies pending settings and connects Claude apps")
            }
        }
    }

    private var routingSection: some View {
        SettingsSection("Model routing") {
            SettingsCard {
                Grid(horizontalSpacing: 14, verticalSpacing: 0) {
                    ForEach(ClaudeRoute.all) { route in
                        SettingsMappingRow(route.displayName) {
                            Picker(
                                route.displayName,
                                selection: Binding<String?>(
                                    get: { model.optionID(for: route.id) },
                                    set: { selection in
                                        let mapping = model.mapping(for: selection)
                                        Task { await onMapping(route.id, mapping) }
                                    }
                                )
                            ) {
                                Text("Not assigned").tag(String?.none)
                                ForEach(model.codexExposureGroups) { group in
                                    Section(group.providerName) {
                                        ForEach(group.options) { option in
                                            Text(option.label).tag(Optional(option.id))
                                        }
                                    }
                                }
                            }
                            .disabled(model.isBusy)
                        }
                    }
                }
            }
            if model.modelOptions.isEmpty {
                Button("Add a Provider…") { model.selectedSection = .providers }
            }
        }
    }

    private var connectionTitle: String {
        if model.connected && model.claudeCodeStatus == .connected { return "Connected" }
        if model.connected { return "Desktop connected" }
        if model.claudeCodeStatus == .connected { return "Terminal connected" }
        return "Not connected"
    }

    private var autoModeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                Text("Auto mode")
                    .font(SettingsLayout.Typography.rowLabel)
                Spacer(minLength: 12)
                Toggle(
                    "Enable auto mode",
                    isOn: Binding(
                        get: { model.autoMode },
                        set: { enabled in Task { await onAutoMode(enabled) } }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(model.isBusy)
            }
            Text("Let Claude decide when to ask before making changes.")
                .settingsSupportingText()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyAllClaudeSettings() async {
        let desktopAction =
            model.canPerformClaudePrimaryAction
            ? model.claudePrimaryAction
            : nil
        let codeAction =
            model.canPerformClaudeCodePrimaryAction
            ? model.claudeCodePrimaryAction
            : nil
        await onApplyAll(desktopAction, codeAction)
    }
}
