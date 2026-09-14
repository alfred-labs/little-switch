import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Provider drafts")
struct ProviderDraftTests {
    @Test("Existing providers preserve identity and normalize sorted context overrides")
    func providerDraftRoundTrip() throws {
        let providerID = try #require(
            UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        )
        let provider = Provider(
            id: providerID,
            name: "z.ai",
            baseURL: "https://api.z.ai/api/anthropic",
            authMode: .bearer,
            models: [
                DiscoveredModel(id: "zeta", contextWindowOverride: 1_000_000),
                DiscoveredModel(id: "alpha", detectedContextWindow: 200_000),
            ],
            maximumParallelRequests: 11,
            imageInputOverride: .enabled,
            responsesWireOverride: .chatCompletions,
            wireProbe: ProviderWireProbe(
                messages: .available,
                responses: .absent,
                chatCompletions: .available
            )
        )

        let draft = ProviderDraft(provider: provider)

        #expect(draft.providerID == provider.id)
        #expect(draft.name == provider.name)
        #expect(draft.baseURL == provider.baseURL)
        #expect(draft.authMode == provider.authMode)
        #expect(draft.maximumParallelRequests == 11)
        #expect(draft.credential.isEmpty)
        #expect(draft.imageInputOverride == .enabled)
        #expect(draft.responsesWireOverride == .chatCompletions)
        #expect(draft.wireProbe?.responses == .absent)
        #expect(draft.modelContexts.map(\.id) == ["alpha", "zeta"])
        #expect(draft.contextsAreValid)
        #expect(draft.contextOverrides == ["zeta": 1_000_000])
    }

    @Test("Fresh drafts leave the image input override on automatic")
    func newProviderOmitsImageInputOverride() {
        let draft = ProviderDraft()
        #expect(draft.imageInputOverride == nil)
        #expect(draft.responsesWireOverride == nil)
        #expect(draft.wireProbe == nil)
    }

    @Test("Applying the OpenAI preset seeds the hosted endpoint without an Anthropic surface")
    func openAIPresetApplies() {
        var draft = ProviderDraft()

        draft.apply(.openAI)

        #expect(draft.name == "openai")
        #expect(draft.baseURL == "https://api.openai.com")
        #expect(draft.authMode == .bearer)
        #expect(draft.anthropicBaseURL.isEmpty)
        #expect(draft.credentialSource == .manual)
        #expect(draft.wireProbe == nil)
    }

    @Test("New providers do not submit context overrides")
    func newProviderOmitsContextOverrides() {
        let draft = ProviderDraft()

        #expect(draft.providerID == nil)
        #expect(draft.name.isEmpty)
        #expect(draft.baseURL.isEmpty)
        #expect(draft.authMode == .none)
        #expect(draft.maximumParallelRequests == Provider.defaultMaximumParallelRequests)
        #expect(draft.credential.isEmpty)
        #expect(draft.modelContexts.isEmpty)
        #expect(draft.contextsAreValid)
        #expect(draft.contextOverrides == nil)
    }

    @Test("Script drafts carry the default refresh period until it is changed")
    func credentialRefreshDraftDefaults() {
        let fresh = ProviderDraft()
        #expect(fresh.scriptPath.isEmpty)
        #expect(fresh.credentialRefreshInterval == Provider.defaultCredentialRefreshInterval)
        #expect(
            fresh.effectiveCredentialRefreshInterval == Provider.defaultCredentialRefreshInterval
        )

        var edited = ProviderDraft()
        edited.credentialRefreshInterval = 900
        #expect(edited.effectiveCredentialRefreshInterval == 900)

        // Clearing the field falls back to the default instead of cadence 0.
        edited.credentialRefreshInterval = nil
        #expect(
            edited.effectiveCredentialRefreshInterval == Provider.defaultCredentialRefreshInterval
        )

        let provider = Provider(
            name: "Vault",
            baseURL: "https://vault.example.com",
            authMode: .bearer,
            credentialSource: .script
        )
        let existing = ProviderDraft(provider: provider)
        #expect(existing.scriptPath.isEmpty)
        #expect(existing.credentialRefreshInterval == Provider.defaultCredentialRefreshInterval)
        #expect(
            existing.effectiveCredentialRefreshInterval == Provider.defaultCredentialRefreshInterval
        )
    }

    @Test("Applying presets updates every preset-owned draft field together")
    func applyPreset() {
        var draft = ProviderDraft()
        draft.credential = "keep-secret"
        draft.wireProbe = ProviderWireProbe(
            messages: .available,
            responses: .absent,
            chatCompletions: .available
        )
        draft.apply(.zai)

        #expect(draft.name == ProviderPreset.zai.name)
        #expect(draft.baseURL == ProviderPreset.zai.baseURL)
        #expect(draft.authMode == ProviderPreset.zai.authMode)
        #expect(draft.maximumParallelRequests == 2)
        // The probe belonged to the previous endpoint; it must not vouch
        // for the preset's URLs.
        #expect(draft.wireProbe == nil)

        draft.apply(.ollama)

        #expect(draft.name == ProviderPreset.ollama.name.lowercased())
        #expect(draft.baseURL == ProviderPreset.ollama.baseURL)
        #expect(draft.authMode == ProviderPreset.ollama.authMode)
        #expect(draft.maximumParallelRequests == 4)
        #expect(draft.credential == "keep-secret")
    }

    @Test("Provider names are always lowercased in drafts")
    func lowercasesProviderNames() {
        var draft = ProviderDraft()
        draft.name = "Example"
        #expect(draft.name == "example")

        let provider = Provider(
            name: "Z.AI",
            baseURL: "https://api.z.ai/api/anthropic",
            authMode: .bearer
        )
        #expect(ProviderDraft(provider: provider).name == "z.ai")
    }

    @Test("Direct provider identity edits preserve the chosen parallel request limit")
    func directIdentityEditsPreserveLimit() {
        var draft = ProviderDraft()
        draft.maximumParallelRequests = 17

        draft.name = "Manually edited"
        draft.baseURL = "https://example.com/v2"

        #expect(draft.maximumParallelRequests == 17)
    }

    @Test("Invalid context rows invalidate existing provider drafts")
    func invalidContextRows() {
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "model")]
        )
        var draft = ProviderDraft(provider: provider)
        draft.modelContexts[0].overrideText = "not-a-context"

        #expect(!draft.contextsAreValid)
        #expect(draft.contextOverrides == nil)
    }
}

extension ProviderDraftTests {
    @Test("Applying the z.ai preset seeds its split chat completions URL")
    func zaiPresetSeedsChatURL() {
        var draft = ProviderDraft()
        draft.apply(.zai)

        #expect(draft.anthropicBaseURL == "https://api.z.ai/api/anthropic")
        #expect(draft.normalizedAnthropicBaseURL == "https://api.z.ai/api/anthropic")
    }

    @Test("A blank chat completions URL maps to nil on input")
    func blankChatURLMapsToNil() {
        var draft = ProviderDraft()
        draft.apply(.zai)
        draft.anthropicBaseURL = "   "

        #expect(draft.normalizedAnthropicBaseURL == nil)
    }
}
