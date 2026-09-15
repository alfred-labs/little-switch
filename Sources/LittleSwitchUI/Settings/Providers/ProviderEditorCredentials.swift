import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI

struct ProviderEditorCredentials: View {
    @Binding var draft: ProviderDraft
    @Binding var isChoosingScript: Bool
    let lastScriptOutput: String?

    var body: some View {
        Section(L10n.resource("Credentials")) {
            Picker(L10n.resource("Credential type"), selection: $draft.authMode) {
                Text(L10n.resource("None")).tag(AuthMode.none)
                Text(verbatim: "Authorization: Bearer").tag(AuthMode.bearer)
                Text(verbatim: "X-Api-Key").tag(AuthMode.xAPIKey)
            }
            .settingsMenuPicker()
            if draft.authMode != .none {
                Picker(L10n.resource("Credential source"), selection: $draft.credentialSource) {
                    Text(L10n.resource("Paste a token")).tag(CredentialSource.manual)
                    Text(L10n.resource("Run a script")).tag(CredentialSource.script)
                }
                .settingsMenuPicker()
                if draft.credentialSource == .script {
                    scriptRow
                    Picker(L10n.resource("Refresh every"), selection: $draft.credentialRefreshInterval) {
                        ForEach(Provider.credentialRefreshIntervalChoices, id: \.self) { seconds in
                            Text(Self.intervalLabel(seconds)).tag(Optional(seconds))
                        }
                    }
                    .settingsMenuPicker()
                    Text(
                        L10n.resource(
                            "The script may open a browser or prompt to log in. Requests use its saved token between runs."
                        )
                    )
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
                    if let lastScriptOutput {
                        DisclosureGroup(L10n.string("Last script output")) {
                            Text(lastScriptOutput)
                                .font(SettingsLayout.Typography.monospacedValue)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    SecureField(L10n.string("API token"), text: $draft.credential)
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
        case .edit: L10n.string("Leave blank to keep the saved key.")
        case .duplicate: L10n.string("Leave blank to reuse the original key.")
        }
    }

    private var scriptRow: some View {
        HStack(spacing: 8) {
            Text(L10n.resource("Credential script"))
            Spacer(minLength: 12)
            Text(
                draft.scriptPath.isEmpty
                    ? L10n.string("No script chosen")
                    : draft.scriptPath
            )
            .font(SettingsLayout.Typography.monospacedValue)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .help(draft.scriptPath)
            if !draft.scriptPath.isEmpty {
                Button(L10n.resource("Clear script"), systemImage: "xmark.circle") { draft.scriptPath = "" }
                    .labelStyle(.iconOnly)
                    .help(L10n.resource("Clear the chosen script"))
            }
            Button(L10n.resource("Choose…")) { isChoosingScript = true }
                .fixedSize()
        }
    }

    private static func intervalLabel(_ seconds: TimeInterval) -> String {
        switch seconds {
        case 300: L10n.string("5 minutes")
        case 900: L10n.string("15 minutes")
        case 1_800: L10n.string("30 minutes")
        case 3_600: L10n.string("1 hour")
        case 21_600: L10n.string("6 hours")
        case 86_400: L10n.string("24 hours")
        default: L10n.string("\(Int(seconds)) seconds")
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

    var title: String {
        switch self {
        case .ollama: L10n.string("Ollama")
        case .openAI: L10n.string("OpenAI")
        case .omlx: L10n.string("oMLX")
        case .lmStudio: L10n.string("LM Studio")
        case .zai: L10n.string("z.ai")
        case .openRouter: L10n.string("OpenRouter")
        case .openAICompatible: L10n.string("OpenAI Compatible")
        case .custom: L10n.string("Custom")
        }
    }

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
