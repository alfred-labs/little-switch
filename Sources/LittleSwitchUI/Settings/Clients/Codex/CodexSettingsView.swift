import LittleSwitchCommon
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
                    Label(L10n.resource("No models"), systemImage: "square.stack.3d.up")
                } description: {
                    Text(L10n.resource("Add and refresh a provider to make its models available."))
                } actions: {
                    Button(L10n.resource("Add a Provider…")) { model.selectedSection = .providers }
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
                Button(
                    model.isBusy
                        ? L10n.string("Applying…")
                        : model.codexPrimaryActionTitle,
                    systemImage: "checkmark"
                ) {
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
        SettingsSection(L10n.resource("Model routing"), subtitle: L10n.resource("For Codex Desktop and CLI.")) {
            SettingsCard {
                Grid(horizontalSpacing: 14, verticalSpacing: 0) {
                    SettingsMappingRow(L10n.string("Default model")) {
                        Picker(
                            L10n.resource("Default model"),
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
                    SettingsMappingRow(L10n.string("Custom approval review")) {
                        Picker(
                            L10n.resource("Custom approval review model"),
                            selection: Binding<ModelMapping?>(
                                get: { model.configuration.codex.autoReviewModel },
                                set: { mapping in Task { await onAutoReview(mapping) } }
                            )
                        ) {
                            Text(L10n.resource("Same as default")).tag(nil as ModelMapping?)
                            ForEach(model.modelOptions) { option in
                                Text(option.label).tag(Optional(option.mapping))
                            }
                            if let mapping = model.configuration.codex.autoReviewModel {
                                if model.hasUnavailableCodexAutoReviewModel {
                                    Text(L10n.resource("Unavailable: \(mapping.modelID)")).tag(Optional(mapping))
                                }
                            }
                        }
                        .disabled(model.isBusy || model.modelOptions.isEmpty)
                        .help(L10n.resource("Reviews requests from custom models for permissions outside the sandbox."))
                    }
                }
            }
            Text(L10n.resource("Native OpenAI models keep Codex's own approval reviewer."))
                .font(SettingsLayout.Typography.supporting)
                .foregroundStyle(.secondary)
            if model.hasUnavailableCodexAutoReviewModel {
                Label(
                    L10n.resource("Choose an available approval review model."), systemImage: "exclamationmark.triangle"
                )
                .font(SettingsLayout.Typography.supporting)
                .foregroundStyle(.orange)
            }
        }
    }
}
