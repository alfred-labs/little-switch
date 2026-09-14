import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI

struct ProvidersSettingsView: View {
    @Bindable var model: AppModel
    let onSave: @MainActor (ProviderInput) async -> ProviderSaveOutcome
    let onTest: @MainActor (ProviderInput) async -> ProviderTestOutcome
    let onRefresh: @MainActor (UUID) async -> Void
    let onDelete: @MainActor (UUID) async -> Void
    @State private var draft: ProviderDraft?
    @State private var providerToDelete: Provider?
    @FocusState private var focusedProvider: UUID?
    @FocusState private var addFocused: Bool
    @State private var returnFocusID: UUID?

    var body: some View {
        SettingsPage {
            SettingsSection("Model providers") {
                SettingsCard {
                    if model.providers.isEmpty {
                        ContentUnavailableView(
                            "No providers",
                            systemImage: "server.rack",
                            description: Text("Add Ollama, oMLX, LM Studio, OpenRouter, or another provider.")
                        )
                    } else {
                        ForEach(model.providers) { provider in
                            HStack(spacing: 12) {
                                Button {
                                    edit(provider)
                                } label: {
                                    ProviderSettingsRow(
                                        provider: provider,
                                        scriptFailure: model.credentialRefreshFailures[provider.id]
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .focused($focusedProvider, equals: provider.id)
                                .accessibilityHint("Edit \(provider.name) settings")
                                Menu {
                                    providerActions(provider)
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .frame(width: 24, height: 24)
                                }
                                .menuIndicator(.hidden)
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .accessibilityLabel("Actions for \(provider.name)")
                            }
                            .disabled(model.isBusy)
                            .contextMenu { providerActions(provider) }
                        }
                    }
                }
                Text("Local and cloud models available to your apps.")
                    .settingsSupportingText()
            }
        }
        .toolbar {
            SettingsToolbarActions {
                Button("Add Provider", systemImage: "plus") {
                    returnFocusID = nil
                    draft = ProviderDraft()
                }
                .disabled(model.isBusy)
                .focused($addFocused)
            }
        }
        .sheet(item: $draft, onDismiss: restoreFocus) { draft in
            ProviderEditor(
                draft: draft,
                providers: model.providers,
                responsesWireVerdict: draft.intent == .edit
                    ? draft.providerID.flatMap { model.responsesWireVerdicts[$0] } : nil,
                lastScriptOutput: draft.intent == .edit
                    ? draft.providerID.flatMap { model.lastScriptOutputs[$0] } : nil,
                onTest: onTest
            ) { input in
                let outcome = await onSave(input)
                if case .saved = outcome { self.draft = nil }
                return outcome
            }
        }
        .alert(
            "Delete “\(providerToDelete?.name ?? "provider")”?",
            isPresented: Binding(
                get: { providerToDelete != nil },
                set: { if !$0 { providerToDelete = nil } }
            ),
            presenting: providerToDelete
        ) { provider in
            Button("Cancel", role: .cancel) { focusedProvider = provider.id }
            Button("Delete Provider", role: .destructive) {
                delete(provider)
            }
        } message: { _ in
            Text("Its models will be removed and routes using them will be cleared.")
        }
    }

    @ViewBuilder
    private func providerActions(_ provider: Provider) -> some View {
        Button("Edit…", systemImage: "pencil") { edit(provider) }
        Button("Duplicate…", systemImage: "plus.square.on.square") {
            returnFocusID = provider.id
            draft = ProviderDraft(duplicating: provider, providers: model.providers)
        }
        Button("Refresh Models", systemImage: "arrow.clockwise") {
            Task { await onRefresh(provider.id) }
        }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) {
            providerToDelete = provider
        }
    }

    private func edit(_ provider: Provider) {
        returnFocusID = provider.id
        draft = ProviderDraft(provider: provider)
    }

    private func restoreFocus() {
        if let returnFocusID, model.providers.contains(where: { $0.id == returnFocusID }) {
            focusedProvider = returnFocusID
        } else {
            addFocused = true
        }
    }

    private func delete(_ provider: Provider) {
        let index = model.providers.firstIndex { $0.id == provider.id } ?? 0
        Task {
            await onDelete(provider.id)
            if model.providers.contains(where: { $0.id == provider.id }) {
                focusedProvider = provider.id
            } else if !model.providers.isEmpty {
                focusedProvider = model.providers[min(index, model.providers.count - 1)].id
            } else {
                addFocused = true
            }
        }
    }
}
