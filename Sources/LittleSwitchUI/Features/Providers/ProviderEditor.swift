import Foundation
import LittleSwitchCore
import SwiftUI
import UniformTypeIdentifiers

/// Save failures remain in the sheet, beside the draft that can resolve them.
enum ProviderSaveOutcome {
    case saved
    case failed(String)
}

enum ProviderTestStage: Equatable {
    case idle
    case passed
    case failed(String)
}

struct ProviderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProviderDraft
    @State private var testing = false
    @State private var saving = false
    @State private var scriptStage = ProviderTestStage.idle
    @State private var authenticationStage = ProviderTestStage.idle
    @State private var isChoosingScript = false
    @State private var testedScriptOutput: String?
    @State private var advancedExpanded: Bool
    @State private var preset = ProviderEditorPreset.custom
    @FocusState private var nameIsFocused: Bool
    let providers: [Provider]
    let responsesWireVerdict: Bool?
    let lastScriptOutput: String?
    let onTest: @MainActor (ProviderInput) async -> ProviderTestOutcome
    let onSave: @MainActor (ProviderInput) async -> ProviderSaveOutcome

    init(
        draft: ProviderDraft,
        providers: [Provider] = [],
        responsesWireVerdict: Bool? = nil,
        lastScriptOutput: String? = nil,
        onTest: @escaping @MainActor (ProviderInput) async -> ProviderTestOutcome,
        onSave: @escaping @MainActor (ProviderInput) async -> ProviderSaveOutcome
    ) {
        _draft = State(initialValue: draft)
        _advancedExpanded = State(initialValue: draft.hasAdvancedOverrides)
        self.providers = providers
        self.responsesWireVerdict = draft.intent == .edit ? responsesWireVerdict : nil
        self.lastScriptOutput = draft.intent == .edit ? lastScriptOutput : nil
        self.onTest = onTest
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(SettingsLayout.Typography.sectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)

            Form {
                connectionSection
                ProviderEditorCredentials(
                    draft: $draft,
                    isChoosingScript: $isChoosingScript,
                    lastScriptOutput: testedScriptOutput ?? lastScriptOutput
                )
                capacitySection
                ProviderEditorAdvanced(
                    draft: $draft,
                    isExpanded: $advancedExpanded,
                    responsesWireVerdict: responsesWireVerdict
                )
            }
            .formStyle(.grouped)
            .disabled(testing || saving)
            .onChange(of: draft.baseURL) { _, _ in
                resetTestStages()
                draft.wireProbe = nil
                draft.namespaceProbe = nil
            }
            .onChange(of: draft.anthropicBaseURL) { _, _ in
                resetTestStages()
                draft.wireProbe = nil
                draft.namespaceProbe = nil
            }
            .onChange(of: draft.credential) { _, _ in resetTestStages() }
            .onChange(of: draft.scriptPath) { _, _ in resetTestStages() }
            .onChange(of: draft.authMode) { _, _ in resetTestStages() }
            .onChange(of: draft.credentialSource) { _, _ in resetTestStages() }
            .onChange(of: draft.contextsAreValid) { _, valid in
                if !valid { advancedExpanded = true }
            }

            Divider()
            footer
        }
        .controlSize(.regular)
        .frame(width: 620, height: 660)
        .onAppear {
            if case .duplicate = draft.intent { nameIsFocused = true }
        }
        .fileImporter(
            isPresented: $isChoosingScript,
            allowedContentTypes: [.shellScript, .unixExecutable, .data]
        ) { result in
            if case .success(let url) = result {
                draft.scriptPath = url.path
            }
        }
    }

    private var title: String {
        switch draft.intent {
        case .add: "Add Provider"
        case .edit: "Edit Provider"
        case .duplicate: "Duplicate Provider"
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            if draft.intent == .add {
                Picker("Preset", selection: $preset) {
                    ForEach(ProviderEditorPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .settingsMenuPicker()
                .onChange(of: preset) { _, selection in
                    draft.apply(selection.providerPreset)
                    advancedExpanded = draft.hasAdvancedOverrides
                }
            }
            TextField("Name", text: $draft.name)
                .focused($nameIsFocused)
            if let message = draft.nameValidationMessage(providers: providers) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
            }
            TextField("Base URL", text: $draft.baseURL)
                .textContentType(.URL)
        }
    }

    private var capacitySection: some View {
        Section {
            Stepper(
                value: $draft.maximumParallelRequests,
                in: Provider.maximumParallelRequestsRange
            ) {
                LabeledContent("Parallel requests") {
                    Text(draft.maximumParallelRequests.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Capacity")
        } footer: {
            Text("Shared by every model and app using this provider.")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if (testing || saving) && draft.credentialSource == .script {
                ProviderEditorNotice.runningScript
            } else if testing || saving {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(testing ? "Testing the connection…" : "Saving provider…")
                        .font(SettingsLayout.Typography.supporting)
                        .foregroundStyle(.secondary)
                }
            } else {
                if draft.credentialSource == .script, scriptStage != .idle {
                    ProviderEditorNotice.stageStatusRow("Test script valid", scriptStage)
                }
                if authenticationStage != .idle {
                    ProviderEditorNotice.stageStatusRow(
                        draft.authMode == .none ? "Connection successful" : "Authentication successful",
                        authenticationStage
                    )
                } else {
                    Text("Test the connection to enable Save.")
                        .font(SettingsLayout.Typography.supporting)
                        .foregroundStyle(.secondary)
                }
            }
            if !draft.contextsAreValid {
                Label("Review the context overrides in Advanced.", systemImage: "exclamationmark.triangle")
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(saving)
                Button(testing ? "Testing…" : "Test Connection") { runTest() }
                    .disabled(!testIsEnabled)
                Button(saving ? "Saving…" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || testing || !testPassed || !formIsValid)
            }
        }
        .padding(20)
    }

    private var formIsValid: Bool {
        draft.nameValidationMessage(providers: providers) == nil
            && !draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.contextsAreValid
    }

    private var testIsEnabled: Bool {
        !testing && !saving && formIsValid
    }

    private var testPassed: Bool {
        authenticationStage == .passed
            && (draft.credentialSource != .script || scriptStage == .passed)
    }

    private func resetTestStages() {
        scriptStage = .idle
        authenticationStage = .idle
        testedScriptOutput = nil
    }

    private func runTest() {
        let input = draft.makeInput()
        testing = true
        resetTestStages()
        Task {
            let outcome = await onTest(input)
            testing = false
            switch outcome {
            case .passed(let scriptOutput):
                testedScriptOutput = scriptOutput
                if draft.credentialSource == .script { scriptStage = .passed }
                authenticationStage = .passed
            case .scriptFailed(let message):
                scriptStage = .failed(message)
            case .authenticationFailed(let message):
                if draft.credentialSource == .script { scriptStage = .passed }
                authenticationStage = .failed(message)
                if draft.hasAdvancedOverrides { advancedExpanded = true }
            }
        }
    }

    private func save() {
        let input = draft.makeInput()
        saving = true
        Task {
            let outcome = await onSave(input)
            saving = false
            switch outcome {
            case .saved: dismiss()
            case .failed(let message):
                authenticationStage = .failed(message)
                if draft.hasAdvancedOverrides { advancedExpanded = true }
            }
        }
    }
}
