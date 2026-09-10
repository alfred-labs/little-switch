import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Provider duplication drafts")
struct ProviderDuplicationDraftTests {
    @Test("A duplicate owns a new provider identity and retains editable settings only")
    func copiesSettingsIntoNewIdentity() throws {
        let source = Provider(
            name: "z.ai",
            baseURL: "https://api.example.com/v1",
            authMode: .bearer,
            credentialSource: .script,
            credentialScriptPath: "/tmp/provider-login.sh",
            credentialRefreshInterval: 900,
            models: [DiscoveredModel(id: "model", contextWindowOverride: 1_000_000)],
            lastRefresh: Date(timeIntervalSince1970: 123),
            status: .ready,
            lastError: "Previous failure",
            maximumParallelRequests: 7,
            imageInputOverride: .enabled,
            responsesWireOverride: .chatCompletions,
            anthropicBaseURL: "https://api.example.com/anthropic",
            wireProbe: ProviderWireProbe(
                messages: .available, responses: .absent, chatCompletions: .available
            )
        )

        let draft = ProviderDraft(duplicating: source, providers: [source])

        #expect(try #require(draft.providerID) != source.id)
        #expect(draft.intent == .duplicate(sourceID: source.id))
        #expect(draft.name == "z.ai copy")
        #expect(draft.baseURL == source.baseURL)
        #expect(draft.anthropicBaseURL == source.anthropicBaseURL)
        #expect(draft.authMode == source.authMode)
        #expect(draft.credentialSource == source.credentialSource)
        #expect(draft.scriptPath == source.credentialScriptPath)
        #expect(draft.credentialRefreshInterval == source.credentialRefreshInterval)
        #expect(draft.maximumParallelRequests == source.maximumParallelRequests)
        #expect(draft.imageInputOverride == source.imageInputOverride)
        #expect(draft.responsesWireOverride == source.responsesWireOverride)
        #expect(draft.contextOverrides == ["model": 1_000_000])
        #expect(draft.credential.isEmpty)
        #expect(draft.wireProbe == nil)
        #expect(draft.hasAdvancedOverrides)
    }

    @Test("Copy names use the first free trimmed case-insensitive suffix")
    func firstAvailableName() {
        let source = Provider(name: " Z.AI ", baseURL: "https://example.com", authMode: .none)
        var second = source
        second.id = UUID()
        second.name = " Z.AI COPY "
        var fourth = source
        fourth.id = UUID()
        fourth.name = "z.ai copy 3"

        let draft = ProviderDraft(duplicating: source, providers: [source, second, fourth])

        #expect(draft.name == "z.ai copy 2")
        #expect(draft.nameValidationMessage(providers: [source, second, fourth]) == nil)
    }

    @Test("Inline name validation allows only the edited provider to keep its name")
    func validatesNamesByIntent() {
        let source = Provider(name: " z.ai ", baseURL: "https://example.com", authMode: .none)
        var duplicate = ProviderDraft(duplicating: source, providers: [source])
        duplicate.name = " Z.AI "
        let edited = ProviderDraft(provider: source)

        #expect(duplicate.nameValidationMessage(providers: [source]) != nil)
        #expect(edited.nameValidationMessage(providers: [source]) == nil)
        #expect(edited.intent == .edit)
        #expect(ProviderDraft().intent == .add)
        duplicate.name = " \n "
        #expect(duplicate.nameValidationMessage(providers: [source]) == "Enter a provider name.")
    }

    @Test("An advanced context error remains an advanced state even without a valid override")
    func advancedContextError() {
        let source = Provider(
            name: "local",
            baseURL: "https://example.com",
            authMode: .none,
            models: [DiscoveredModel(id: "model")]
        )
        var draft = ProviderDraft(provider: source)
        #expect(!draft.hasAdvancedOverrides)
        draft.modelContexts[0].overrideText = "invalid"

        #expect(draft.hasAdvancedOverrides)
        #expect(!draft.contextsAreValid)
    }
}
