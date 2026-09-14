import SwiftUI

struct ProviderEditorAdvanced: View {
    @Binding var draft: ProviderDraft
    @Binding var isExpanded: Bool
    @State private var connectionDetailsExpanded = false
    let responsesWireVerdict: Bool?

    var body: some View {
        Section {
            if isExpanded {
                ProviderEditorCompatibility(draft: $draft)
            }
        } header: {
            VStack(alignment: .leading, spacing: 8) {
                DisclosureGroup("Advanced", isExpanded: $isExpanded) {}
                    .font(SettingsLayout.Typography.disclosureTitle)
                    .foregroundStyle(.primary)
                    .accessibilityHint("Show or hide advanced provider settings")
                if isExpanded { Text("Compatibility") }
            }
        } footer: {
            if isExpanded {
                Text(
                    draft.disabledThinkingOverride == .lowEffort
                        ? "Low effort applies only when the request does not specify an effort."
                        : "Pass through preserves the caller's thinking parameters."
                )
            }
        }

        if isExpanded {
            if !draft.modelContexts.isEmpty {
                ProviderModelContextTable(contexts: $draft.modelContexts)
            }
            Section {
                ProviderEditorConnectionDetails(
                    isExpanded: $connectionDetailsExpanded,
                    responsesWireOverride: draft.responsesWireOverride,
                    learnedVerdict: responsesWireVerdict,
                    wireProbe: draft.wireProbe
                )
            }
        }
    }
}
