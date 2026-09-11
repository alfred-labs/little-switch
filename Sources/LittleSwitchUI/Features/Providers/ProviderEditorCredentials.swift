import Foundation
import LittleSwitchCore
import SwiftUI

struct ProviderEditorCredentials: View {
    @Binding var draft: ProviderDraft
    @Binding var isChoosingScript: Bool
    let lastScriptOutput: String?

    var body: some View {
        Section("Credentials") {
            Picker("Credential type", selection: $draft.authMode) {
                Text("None").tag(AuthMode.none)
                Text("Authorization: Bearer").tag(AuthMode.bearer)
                Text("X-Api-Key").tag(AuthMode.xAPIKey)
            }
            .settingsMenuPicker()
            if draft.authMode != .none {
                Picker("Credential source", selection: $draft.credentialSource) {
                    Text("Paste a token").tag(CredentialSource.manual)
                    Text("Run a script").tag(CredentialSource.script)
                }
                .settingsMenuPicker()
                if draft.credentialSource == .script {
                    scriptRow
                    Picker("Refresh every", selection: $draft.credentialRefreshInterval) {
                        ForEach(Provider.credentialRefreshIntervalChoices, id: \.self) { seconds in
                            Text(Self.intervalLabel(seconds)).tag(Optional(seconds))
                        }
                    }
                    .settingsMenuPicker()
                    Text(
                        "The script may open a browser or prompt to log in. Requests use its saved token between runs."
                    )
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
                    if let lastScriptOutput {
                        DisclosureGroup("Last script output") {
                            Text(lastScriptOutput)
                                .font(SettingsLayout.Typography.monospacedValue)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    SecureField("API token", text: $draft.credential)
                    if let credentialHelp {
                        Text(credentialHelp)
                            .font(SettingsLayout.Typography.supporting)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var credentialHelp: String? {
        switch draft.intent {
        case .add: nil
        case .edit: "Leave blank to keep the saved key."
        case .duplicate: "Leave blank to reuse the original key."
        }
    }

    private var scriptRow: some View {
        HStack(spacing: 8) {
            Text("Credential script")
            Spacer(minLength: 12)
            Text(draft.scriptPath.isEmpty ? "No script chosen" : draft.scriptPath)
                .font(SettingsLayout.Typography.monospacedValue)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help(draft.scriptPath)
            if !draft.scriptPath.isEmpty {
                Button("Clear script", systemImage: "xmark.circle") { draft.scriptPath = "" }
                    .labelStyle(.iconOnly)
                    .help("Clear the chosen script")
            }
            Button("Choose…") { isChoosingScript = true }
                .fixedSize()
        }
    }

    private static func intervalLabel(_ seconds: TimeInterval) -> String {
        switch seconds {
        case 300: "5 minutes"
        case 900: "15 minutes"
        case 1_800: "30 minutes"
        case 3_600: "1 hour"
        case 21_600: "6 hours"
        case 86_400: "24 hours"
        default: "\(Int(seconds)) seconds"
        }
    }
}

enum ProviderEditorPreset: String, CaseIterable, Identifiable {
    case ollama = "Ollama"
    case openAI = "OpenAI"
    case omlx = "oMLX"
    case lmStudio = "LM Studio"
    case zai = "z.ai"
    case openRouter = "OpenRouter"
    case openAICompatible = "OpenAI Compatible"
    case custom = "Custom"

    var id: String { rawValue }

    var providerPreset: ProviderPreset {
        switch self {
        case .ollama: .ollama
        case .openAI: .openAI
        case .omlx: .omlx
        case .lmStudio: .lmStudio
        case .zai: .zai
        case .openRouter: .openRouter
        case .openAICompatible: .openAICompatible
        case .custom: .custom
        }
    }
}
