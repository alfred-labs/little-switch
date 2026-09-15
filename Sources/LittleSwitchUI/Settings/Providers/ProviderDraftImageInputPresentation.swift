import LittleSwitchCommon

extension ProviderModelImageInputPresentation {
    static func forDraft(
        _ draft: ProviderDraft,
        providers: [Provider],
        learnedNative: Bool?,
        diagnostics: [ModelImageInputProbeDiagnostic]
    ) -> [String: Self] {
        let stored = draft.intent == .edit ? providers.first { $0.id == draft.providerID } : nil
        var provider = Provider(
            id: draft.providerID ?? draft.id,
            name: draft.name,
            baseURL: draft.baseURL,
            authMode: draft.authMode,
            credentialSource: draft.credentialSource,
            credentialScriptPath: draft.scriptPath.isEmpty ? nil : draft.scriptPath,
            models: stored?.models ?? draft.modelContexts.map { DiscoveredModel(id: $0.id) },
            imageInputOverride: draft.imageInputOverride,
            responsesWireOverride: draft.responsesWireOverride,
            anthropicBaseURL: draft.anthropicBaseURL.isEmpty ? nil : draft.anthropicBaseURL,
            wireProbe: draft.wireProbe)
        let sameIdentity = stored?.hasSameImageInputIdentity(as: provider) == true && draft.credential.isEmpty
        if let stored, sameIdentity { provider.imageInputObservations = stored.imageInputObservations }
        return Dictionary(
            uniqueKeysWithValues: provider.models.map { model in
                (
                    model.id,
                    make(
                        provider: provider,
                        model: model,
                        learnedNative: sameIdentity ? learnedNative : nil,
                        diagnostics: sameIdentity ? diagnostics : [])
                )
            })
    }
}
