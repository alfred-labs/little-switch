import Foundation
import LittleSwitchCommon
import LittleSwitchCore

struct ProviderDraft: Identifiable {
    let id = UUID()
    var providerID: UUID?
    private(set) var intent = ProviderMutationIntent.add
    private var nameStorage = ""
    var baseURL = ""
    var authMode = AuthMode.none
    /// Where the credential comes from when a header is sent.
    var credentialSource = CredentialSource.manual
    var maximumParallelRequests = Provider.defaultMaximumParallelRequests
    var credential = ""
    /// Path of the credential script chosen in the file system. Left blank
    /// for an existing script provider, the configured path is kept.
    var scriptPath = ""
    var credentialRefreshInterval: TimeInterval?
    var imageInputOverride: ProviderImageInputOverride?
    var disabledThinkingOverride: ProviderDisabledThinkingOverride = .default
    var responsesWireOverride: ProviderResponsesWireOverride?
    var wireProbe: ProviderWireProbe?
    /// The provider's optional Anthropic surface; empty means the base URL
    /// serves every wire.
    var anthropicBaseURL = ""
    var modelContexts: [ModelContextDraft] = []

    var name: String {
        get { nameStorage }
        set { nameStorage = newValue.lowercased() }
    }

    var effectiveCredentialRefreshInterval: TimeInterval {
        credentialRefreshInterval ?? Provider.defaultCredentialRefreshInterval
    }

    var contextsAreValid: Bool {
        modelContexts.allSatisfy(\.isValid)
    }

    var contextOverrides: [String: Int]? {
        guard intent != .add || !modelContexts.isEmpty else {
            return nil
        }
        return try? ModelContextDraft.contextOverrides(from: modelContexts)
    }

    init() {
        credentialRefreshInterval = Provider.defaultCredentialRefreshInterval
    }

    mutating func apply(_ preset: ProviderPreset) {
        name = preset.name
        baseURL = preset.baseURL
        authMode = preset.authMode
        credentialSource = .manual
        maximumParallelRequests = preset.maximumParallelRequests
        disabledThinkingOverride = .default
        anthropicBaseURL = preset.anthropicBaseURL ?? ""
        // The route probe belongs to the previous endpoint: it must not
        // vouch for the preset's URLs.
        wireProbe = nil
    }

    init(provider: Provider) {
        intent = .edit
        providerID = provider.id
        name = provider.name
        baseURL = provider.baseURL
        authMode = provider.authMode
        credentialSource = provider.credentialSource
        scriptPath = provider.credentialScriptPath ?? ""
        maximumParallelRequests = provider.maximumParallelRequests
        credentialRefreshInterval =
            provider.credentialRefreshInterval ?? Provider.defaultCredentialRefreshInterval
        imageInputOverride = provider.imageInputOverride
        disabledThinkingOverride = provider.disabledThinkingOverride
        responsesWireOverride = provider.responsesWireOverride
        anthropicBaseURL = provider.anthropicBaseURL ?? ""
        wireProbe = provider.wireProbe
        modelContexts = provider.models.map(ModelContextDraft.init).sorted { $0.id < $1.id }
    }

    init(duplicating provider: Provider, providers: [Provider]) {
        self.init(provider: provider)
        providerID = UUID()
        intent = .duplicate(sourceID: provider.id)
        name = ProviderNameValidation.availableCopyName(of: provider.name, providers: providers)
        wireProbe = nil
    }

    var hasAdvancedOverrides: Bool {
        normalizedAnthropicBaseURL != nil
            || imageInputOverride != nil
            || disabledThinkingOverride != .default
            || responsesWireOverride != nil
            || modelContexts.contains { !$0.overrideText.isEmpty }
    }

    var normalizedAnthropicBaseURL: String? {
        let value = anthropicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func makeInput() -> ProviderInput {
        ProviderInput(
            id: providerID,
            intent: intent,
            name: name,
            baseURL: baseURL,
            authMode: authMode,
            credential: credential,
            credentialSource: credentialSource,
            scriptPath: scriptPath,
            credentialRefreshInterval: effectiveCredentialRefreshInterval,
            contextOverrides: contextOverrides,
            maximumParallelRequests: maximumParallelRequests,
            imageInputOverride: imageInputOverride,
            disabledThinkingOverride: disabledThinkingOverride,
            responsesWireOverride: responsesWireOverride,
            anthropicBaseURL: normalizedAnthropicBaseURL
        )
    }

    func nameValidationMessage(providers: [Provider]) -> String? {
        ProviderNameValidation.message(
            name, providers: providers, excluding: intent == .edit ? providerID : nil
        )
    }
}
