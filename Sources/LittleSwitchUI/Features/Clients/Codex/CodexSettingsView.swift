import LittleSwitchCore
import SwiftUI

struct CodexSettingsView: View {
    @Bindable var model: AppModel
    let onExposure: @MainActor ([ModelMapping], Bool) async -> Void
    let onDefault: @MainActor (ModelMapping?) async -> Void
    let onAutoReview: @MainActor (ModelMapping?) async -> Void
    let onConnect: @MainActor () async -> Void
    let onApply: @MainActor () async -> Void

    var body: some View {
        SettingsPage {
            routingSection
            if model.modelOptions.isEmpty {
                ContentUnavailableView {
                    Label("No models", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Add and refresh a provider to make its models available.")
                } actions: {
                    Button("Add a Provider…") { model.selectedSection = .providers }
                }
            } else {
                ModelCatalogView(model: model, onExposure: onExposure)
            }
        }
        .toolbar {
            SettingsToolbarActions {
                if model.hasPendingCodexChanges {
                    SettingsPendingNotice()
                } else {
                    SettingsConnectionStatus(connected: model.codexConnected)
                }
                Button(model.isBusy ? "Applying…" : model.codexPrimaryActionTitle, systemImage: "checkmark") {
                    let action = model.codexPrimaryAction
                    Task {
                        switch action {
                        case .connect: await onConnect()
                        case .apply: await onApply()
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canPerformCodexPrimaryAction)
                .accessibilityHint(model.codexPrimaryActionAccessibilityHint)
                .accessibilityValue(model.codexPrimaryActionAccessibilityValue)
            }
        }
    }

    private var routingSection: some View {
        SettingsSection("Model routing", subtitle: "For Codex Desktop and CLI.") {
            SettingsCard {
                Grid(horizontalSpacing: 14, verticalSpacing: 0) {
                    SettingsMappingRow("Default model") {
                        Picker(
                            "Default model",
                            selection: Binding<String?>(
                                get: { model.codexDefaultOptionID },
                                set: { optionID in
                                    let mapping = model.mapping(for: optionID)
                                    Task { await onDefault(mapping) }
                                }
                            )
                        ) {
                            ForEach(model.codexExposedModelOptions) { option in
                                Text(option.label).tag(Optional(option.id))
                            }
                        }
                        .disabled(model.isBusy || model.codexExposedModelOptions.isEmpty)
                    }
                    SettingsMappingRow("Approval review model") {
                        Picker(
                            "Approval review model",
                            selection: Binding<ModelMapping?>(
                                get: { model.configuration.codex.autoReviewModel },
                                set: { mapping in Task { await onAutoReview(mapping) } }
                            )
                        ) {
                            Text("Same as default").tag(nil as ModelMapping?)
                            ForEach(model.modelOptions) { option in
                                Text(option.label).tag(Optional(option.mapping))
                            }
                            if let mapping = model.configuration.codex.autoReviewModel {
                                if model.hasUnavailableCodexAutoReviewModel {
                                    Text("Unavailable: \(mapping.modelID)").tag(Optional(mapping))
                                }
                            }
                        }
                        .disabled(model.isBusy || model.modelOptions.isEmpty)
                        .help("Reviews requests for permissions outside the sandbox.")
                    }
                }
            }
            if model.hasUnavailableCodexAutoReviewModel {
                Label("Choose an available approval review model.", systemImage: "exclamationmark.triangle")
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.orange)
            }
        }
    }
}
