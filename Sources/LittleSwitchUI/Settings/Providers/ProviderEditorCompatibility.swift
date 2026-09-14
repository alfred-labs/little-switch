import LittleSwitchCommon
import SwiftUI

/// Editable compatibility choices stay together, separate from detected state.
struct ProviderEditorCompatibility: View {
    @Binding var draft: ProviderDraft

    var body: some View {
        TextField("Anthropic URL", text: $draft.anthropicBaseURL, prompt: Text("Optional"))
            .textContentType(.URL)
        LabeledContent("Responses format") {
            Picker("Responses format", selection: $draft.responsesWireOverride) {
                Text("Automatic").tag(ProviderResponsesWireOverride?.none)
                Text("Native /v1/responses").tag(Optional(ProviderResponsesWireOverride.native))
                Text("Chat completions").tag(Optional(ProviderResponsesWireOverride.chatCompletions))
            }
            .labelsHidden()
            .settingsMenuPicker(width: SettingsLayout.ProviderEditor.controlWidth)
        }
        LabeledContent("Image input") {
            Picker("Image input", selection: $draft.imageInputOverride) {
                Text("Automatic").tag(ProviderImageInputOverride?.none)
                Text("Always allowed").tag(Optional(ProviderImageInputOverride.enabled))
                Text("Disabled").tag(Optional(ProviderImageInputOverride.disabled))
            }
            .labelsHidden()
            .settingsMenuPicker(width: SettingsLayout.ProviderEditor.controlWidth)
        }
        LabeledContent("When thinking is off") {
            Picker("When thinking is off", selection: $draft.disabledThinkingOverride) {
                Text("Use low effort").tag(ProviderDisabledThinkingOverride.lowEffort)
                Text("Pass through").tag(ProviderDisabledThinkingOverride.passthrough)
            }
            .labelsHidden()
            .settingsMenuPicker(width: SettingsLayout.ProviderEditor.controlWidth)
        }
    }
}
