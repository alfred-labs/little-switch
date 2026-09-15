import SwiftUI

struct ProviderEditorAdvanced: View {
    @Binding var draft: ProviderDraft
    @Binding var isExpanded: Bool
    // periphery:ignore - Native SwiftUI state is referenced through $connectionDetailsExpanded.
    @State private var connectionDetailsExpanded = false
    let responsesWireVerdict: Bool?
    var imagePresentations: [String: ProviderModelImageInputPresentation] = [:]

    var body: some View {
        Section {
            if isExpanded {
                ProviderEditorCompatibility(draft: $draft)
            }
        } header: {
            VStack(alignment: .leading, spacing: 8) {
                DisclosureGroup(L10n.string("Advanced"), isExpanded: $isExpanded) {}
                    .font(SettingsLayout.Typography.disclosureTitle)
                    .foregroundStyle(.primary)
                    .accessibilityHint(L10n.string("Show or hide advanced provider settings"))
                if isExpanded { Text(L10n.resource("Compatibility")) }
            }
        } footer: {
            if isExpanded {
                Text(

                    draft.disabledThinkingOverride == .lowEffort
                        ? L10n.resource(
                            "Low effort applies only when the request does not specify an effort."
                        )
                        : L10n.resource(
                            "Pass through preserves the caller's thinking parameters."
                        )
                )
            }
        }

        if isExpanded {
            if !draft.modelContexts.isEmpty {
                ProviderModelContextTable(contexts: $draft.modelContexts, imagePresentations: imagePresentations)
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
