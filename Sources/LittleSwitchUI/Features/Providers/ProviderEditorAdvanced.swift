import LittleSwitchCore
import SwiftUI

struct ProviderEditorAdvanced: View {
    @Binding var draft: ProviderDraft
    @Binding var isExpanded: Bool
    let responsesWireVerdict: Bool?

    var body: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $isExpanded) {
                TextField("Anthropic URL", text: $draft.anthropicBaseURL, prompt: Text("Optional"))
                    .textContentType(.URL)
                ProviderWireRows(
                    responsesWireOverride: $draft.responsesWireOverride,
                    learnedVerdict: responsesWireVerdict,
                    wireProbe: draft.wireProbe,
                    namespaceProbe: draft.namespaceProbe
                )
                Picker("Image input", selection: $draft.imageInputOverride) {
                    Text("Automatic").tag(ProviderImageInputOverride?.none)
                    Text("Always allowed").tag(Optional(ProviderImageInputOverride.enabled))
                    Text("Disabled").tag(Optional(ProviderImageInputOverride.disabled))
                }
                .settingsMenuPicker()
                Picker("Disabled thinking", selection: $draft.disabledThinkingOverride) {
                    Text("Pass through").tag(ProviderDisabledThinkingOverride?.none)
                    Text("Use low effort").tag(Optional(ProviderDisabledThinkingOverride.lowEffort))
                }
                .settingsMenuPicker()
                Text(
                    "With “Use low effort” selected, requests that disable thinking use low effort unless an effort is already set."
                )
                .font(SettingsLayout.Typography.supporting)
                .foregroundStyle(.secondary)
                if !draft.modelContexts.isEmpty {
                    ProviderModelContextRows(contexts: $draft.modelContexts)
                }
            }
        }
    }
}

private struct ProviderModelContextRows: View {
    @Binding var contexts: [ModelContextDraft]

    var body: some View {
        Text("Model context")
            .font(SettingsLayout.Typography.sectionTitle)
        ForEach($contexts) { $context in
            VStack(alignment: .leading, spacing: 5) {
                Toggle(isOn: $context.declares1MManually) {
                    HStack {
                        Text(context.id)
                            .font(SettingsLayout.Typography.monospacedValue)
                            .lineLimit(1)
                            .help(context.id)
                        Spacer()
                        Text("1M")
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(!context.allows1MOverride)
                .accessibilityLabel("Expose 1M context for \(context.id)")
                .help(
                    context.allows1MOverride
                        ? "Expose both the standard and [1m] Claude references"
                        : "Detected capacity is below 1M"
                )
                Text(context.detail)
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(context.isValid ? Color.secondary : Color.red)
            }
        }
        Text("Enable 1M to expose both the standard model reference and its [1m] variant in Claude.")
            .font(SettingsLayout.Typography.supporting)
            .foregroundStyle(.secondary)
    }
}
