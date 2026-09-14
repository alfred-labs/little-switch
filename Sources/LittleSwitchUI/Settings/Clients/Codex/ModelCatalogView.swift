import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI

struct ModelCatalogView: View {
    @Bindable var model: AppModel
    let onExposure: @MainActor ([ModelMapping], Bool) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionContentSpacing) {
            ModelCatalogHeader(enabledCount: model.codexExposedModelOptions.count)
            LazyVStack(spacing: SettingsLayout.sectionContentSpacing) {
                ForEach(model.codexExposureGroups) { group in
                    SettingsCard {
                        DisclosureGroup(isExpanded: expansion(for: group.id)) {
                            ForEach(group.options) { option in
                                modelRow(option)
                            }
                        } label: {
                            Text(ModelCatalogProviderName.title(group.providerName))
                                .lineLimit(1)
                        }
                        .disclosureGroupStyle(
                            SettingsDisclosureGroupStyle(
                                accessibilityHint: "Show or hide models for this provider."
                            ) {
                                providerControls(group)
                            }
                        )
                        .font(SettingsLayout.Typography.disclosureTitle)
                    }
                }
            }
            Text("Shared with OpenCode. New models are enabled automatically.")
                .settingsSupportingText()
        }
    }

    private func expansion(for providerID: UUID) -> Binding<Bool> {
        Binding(
            get: { model.expandedCodexCatalogProviderIDs.contains(providerID) },
            set: { expanded in
                if expanded {
                    model.expandedCodexCatalogProviderIDs.insert(providerID)
                } else {
                    model.expandedCodexCatalogProviderIDs.remove(providerID)
                }
            }
        )
    }

    private func providerControls(_ group: ModelOptionGroup) -> some View {
        let exposedCount = group.options.count { model.isCodexModelExposed($0.mapping) }
        let providerName = ModelCatalogProviderName.title(group.providerName)
        return HStack(alignment: .center, spacing: 10) {
            Text("\(exposedCount) of \(group.options.count)")
                .monospacedDigit()
                .font(SettingsLayout.Typography.supporting)
                .foregroundStyle(.secondary)
            Toggle(
                providerName,
                isOn: Binding(
                    get: { group.options.allSatisfy { model.isCodexModelExposed($0.mapping) } },
                    set: { exposed in
                        let mappings = group.options.map(\.mapping)
                        Task { await onExposure(mappings, exposed) }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(
                model.isBusy
                    || group.options.allSatisfy {
                        $0.mapping == model.configuration.codex.defaultModel
                    }
            )
            .accessibilityLabel("Enable all models from \(providerName)")
            .accessibilityValue("\(exposedCount) of \(group.options.count) models enabled")
            .help("Enable or hide all listed models. The default model stays available.")
        }
        .fixedSize()
    }

    private func modelRow(_ option: ModelOption) -> some View {
        let isDefault = model.configuration.codex.defaultModel == option.mapping
        return HStack(spacing: 10) {
            Text(option.modelID)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(option.label)
            Spacer(minLength: 8)
            if isDefault {
                Text("Default")
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
            }
            Toggle(
                option.modelID,
                isOn: Binding(
                    get: { model.isCodexModelExposed(option.mapping) },
                    set: { exposed in Task { await onExposure([option.mapping], exposed) } }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(model.isBusy || isDefault)
            .help(isDefault ? "Choose another default model before hiding this model." : option.label)
            .accessibilityLabel(option.label)
            .accessibilityHint(
                isDefault ? "Choose another default model before hiding this model." : "Available to Codex and OpenCode"
            )
        }
        .font(SettingsLayout.Typography.rowLabel)
        .frame(minHeight: SettingsLayout.catalogModelRowMinimumHeight)
    }
}
