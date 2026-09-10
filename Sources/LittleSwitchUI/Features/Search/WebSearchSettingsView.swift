import LittleSwitchCore
import SwiftUI

struct WebSearchSettingsView: View {
    @Bindable var model: AppModel
    let onSave: @MainActor (WebSearchInput) async -> Bool
    let onDraft: @MainActor (WebSearchInput?) async -> Void
    @State private var draft: WebSearchDraft

    init(
        model: AppModel,
        onSave: @escaping @MainActor (WebSearchInput) async -> Bool,
        onDraft: @escaping @MainActor (WebSearchInput?) async -> Void
    ) {
        self.model = model
        self.onSave = onSave
        self.onDraft = onDraft
        _draft = State(
            initialValue: WebSearchDraft(
                configuration: model.configuration.webSearch,
                pending: model.webSearchDraft
            )
        )
    }

    var body: some View {
        SettingsPage {
            SettingsSection("Search provider") {
                SettingsCard {
                    WebSearchProviderPicker(
                        selection: Binding(
                            get: { draft.provider },
                            set: { draft.select(provider: $0) }
                        )
                    )
                    .disabled(model.isBusy)
                }
            }
            if let connectionTitle = draft.connectionTitle {
                SettingsSection(connectionTitle) {
                    SettingsCard {
                        LabeledContent("API key") {
                            SecureField(
                                "API key",
                                text: $draft.credential,
                                prompt: Text(draft.credentialPresentation.placeholder)
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 300)
                            .disabled(model.isBusy)
                            .accessibilityLabel("API key")
                            .accessibilityHint(draft.credentialPresentation.accessibilityHint)
                        }
                        .settingsRow()
                    }
                }
                SettingsSection("Usage limits") {
                    SettingsCard {
                        Stepper(value: $draft.resultsLimit, in: draft.resultsRange) {
                            usageLabel(
                                "Results per search",
                                detail: "More results consume more context.",
                                value: draft.resultsLimit)
                        }
                        .padding(.vertical, 6)
                        Stepper(value: $draft.maximumUses, in: WebSearchDraft.maximumUsesRange) {
                            usageLabel("Maximum searches", detail: maximumSearchesDetail, value: draft.maximumUses)
                        }
                        .padding(.vertical, 6)
                    }
                    Text("Limits apply to each response.")
                        .settingsSupportingText()
                }
                .disabled(model.isBusy)
            }
            Label(
                draft.provider == .disabled ? "Web search is disabled." : "Changes apply to new requests.",
                systemImage: "info.circle"
            )
            .settingsSupportingText()
        }
        .toolbar {
            SettingsToolbarActions {
                if hasPendingChanges { SettingsPendingNotice() }
                Button(model.isBusy ? "Applying…" : "Apply", systemImage: "checkmark") { applyDraft() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!canApply)
                    .accessibilityHint("Apply web search settings")
            }
        }
        .onChange(of: model.configuration.webSearch) { _, configuration in
            draft = WebSearchDraft(configuration: configuration, pending: model.webSearchDraft)
        }
        .onDisappear {
            let input = draft.input
            Task { await onDraft(input) }
        }
    }

    private var hasPendingChanges: Bool {
        !draft.input.matches(model.configuration.webSearch)
    }

    private var canApply: Bool {
        !model.isBusy && hasPendingChanges
    }

    private func applyDraft() {
        let input = draft.input
        Task {
            if await onSave(input) {
                draft = WebSearchDraft(configuration: model.configuration.webSearch)
            }
        }
    }

    private func usageLabel(
        _ title: String,
        detail: String,
        value: Int
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SettingsLayout.Typography.rowLabel)
                Text(detail)
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(value.formatted())
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
        }
    }

    private var maximumSearchesDetail: String {
        switch draft.provider {
        case .firecrawl:
            "Each Firecrawl Cloud search may consume credits."
        case .tavily:
            "Each Tavily search may consume credits."
        case .brave:
            "Each Brave search may consume credits."
        case .exa:
            "Each Exa search may consume credits."
        case .disabled:
            "Each search may consume credits."
        }
    }

}
