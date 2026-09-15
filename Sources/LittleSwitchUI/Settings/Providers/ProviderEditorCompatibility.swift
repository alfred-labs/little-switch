import LittleSwitchCommon
import SwiftUI

/// Editable compatibility choices stay together, separate from detected state.
struct ProviderEditorCompatibility: View {
    @Binding var draft: ProviderDraft

    var body: some View {
        TextField(L10n.string("Anthropic URL"), text: $draft.anthropicBaseURL, prompt: Text(L10n.resource("Optional")))
            .textContentType(.URL)
        LabeledContent(L10n.string("Responses format")) {
            Picker(L10n.resource("Responses format"), selection: $draft.responsesWireOverride) {
                Text(L10n.resource("Automatic")).tag(ProviderResponsesWireOverride?.none)
                Text(L10n.resource("Native /v1/responses")).tag(Optional(ProviderResponsesWireOverride.native))
                Text(L10n.resource("Chat completions")).tag(Optional(ProviderResponsesWireOverride.chatCompletions))
            }
            .labelsHidden()
            .settingsMenuPicker(width: SettingsLayout.ProviderEditor.controlWidth)
        }
        LabeledContent(L10n.string("Image input")) {
            Picker(L10n.resource("Image input"), selection: $draft.imageInputOverride) {
                Text(L10n.resource("Automatic")).tag(ProviderImageInputOverride?.none)
                Text(L10n.resource("Always allowed")).tag(Optional(ProviderImageInputOverride.enabled))
                Text(L10n.resource("Disabled")).tag(Optional(ProviderImageInputOverride.disabled))
            }
            .labelsHidden()
            .settingsMenuPicker(width: SettingsLayout.ProviderEditor.controlWidth)
        }
        LabeledContent(L10n.string("When thinking is off")) {
            Picker(L10n.resource("When thinking is off"), selection: $draft.disabledThinkingOverride) {
                Text(L10n.resource("Use low effort")).tag(ProviderDisabledThinkingOverride.lowEffort)
                Text(L10n.resource("Pass through")).tag(ProviderDisabledThinkingOverride.passthrough)
            }
            .labelsHidden()
            .settingsMenuPicker(width: SettingsLayout.ProviderEditor.controlWidth)
        }
    }
}
