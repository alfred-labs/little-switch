import LittleSwitchCore
import SwiftUI

struct WebSearchSettingsView: View {
    @Bindable var model: AppModel
    let onSave: @MainActor (WebSearchInput) async -> Bool
    let onDraft: @MainActor (WebSearchPendingSettings?) -> Void
    @State private var draft: WebSearchDraft

    init(
        model: AppModel,
        onSave: @escaping @MainActor (WebSearchInput) async -> Bool,
        onDraft: @escaping @MainActor (WebSearchPendingSettings?) -> Void
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
            SettingsSection(L10n.resource("Search provider")) {
                SettingsCard {
                    WebSearchProviderPicker(
                        selection: Binding(
                            get: { draft.provider },
                            set: { provider in
                                var updated = draft
                                updated.select(provider: provider)
                                updateDraft(updated)
                            }
                        )
                    )
                    .disabled(model.isBusy)
                }
            }
            if let connectionTitle = draft.connectionTitle {
                SettingsSection(connectionTitle) {
                    SettingsCard {
                        LabeledContent(L10n.string("API key")) {
                            SecureField(
                                L10n.resource("API key"),
                                text: draftBinding.credential,
                                prompt: Text(draft.credentialPresentation.placeholder)
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 300)
                            .disabled(model.isBusy)
                            .accessibilityLabel(L10n.resource("API key"))
                            .accessibilityHint(draft.credentialPresentation.accessibilityHint)
                        }
                        .settingsRow()
                    }
                }
                SettingsSection(L10n.resource("Usage limits")) {
                    SettingsCard {
                        Stepper(value: draftBinding.resultsLimit, in: draft.resultsRange) {
                            usageLabel(
                                L10n.resource("Results per search"),
                                detail: L10n.resource(
                                    "More results consume more context."
                                ),
                                value: draft.resultsLimit)
                        }
                        .padding(.vertical, 6)
                        Stepper(value: draftBinding.maximumUses, in: WebSearchDraft.maximumUsesRange) {
                            usageLabel(
                                L10n.resource("Maximum searches"),
                                detail: maximumSearchesDetail,
                                value: draft.maximumUses
                            )
                        }
                        .padding(.vertical, 6)
                    }
                    Text(L10n.resource("Limits apply to each response."))
                        .settingsSupportingText()
                }
                .disabled(model.isBusy)
            }
            Label(

                draft.provider == .disabled
                    ? L10n.resource("Web search is disabled.")
                    : L10n.resource("Changes apply to new requests."),
                systemImage: "info.circle"
            )
            .settingsSupportingText()
        }
        .toolbar {
            SettingsToolbarActions {
                if hasPendingChanges { SettingsPendingNotice() }
                Button(
                    model.isBusy ? L10n.string("Applying…") : L10n.string("Apply"),
                    systemImage: "checkmark"
                ) { applyDraft() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!canApply)
                .accessibilityHint(L10n.string("Apply web search settings"))
            }
        }
        .onChange(of: model.configuration.webSearch) { previous, applied in
            var updated = draft
            updated.rebase(on: applied, replacing: previous)
            updateDraft(updated)
        }
        .onDisappear {
            var cleared = draft
            cleared.credential = ""
            updateDraft(cleared)
        }
    }

    private var draftBinding: Binding<WebSearchDraft> {
        Binding(get: { draft }, set: updateDraft)
    }

    private func updateDraft(_ value: WebSearchDraft) {
        draft = value
        let pending = value.pending.matches(model.configuration.webSearch) ? nil : value.pending
        onDraft(pending)
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
                updateDraft(WebSearchDraft(configuration: model.configuration.webSearch))
            }
        }
    }

    private func usageLabel(
        _ title: LocalizedStringResource,
        detail: LocalizedStringResource,
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

    private var maximumSearchesDetail: LocalizedStringResource {
        switch draft.provider {
        case .firecrawl:
            L10n.resource("Each Firecrawl Cloud search may consume credits.")
        case .tavily:
            L10n.resource("Each Tavily search may consume credits.")
        case .brave:
            L10n.resource("Each Brave search may consume credits.")
        case .exa:
            L10n.resource("Each Exa search may consume credits.")
        case .disabled:
            L10n.resource("Each search may consume credits.")
        }
    }

}
