import LittleSwitchCommon
import Testing

@testable import LittleSwitchUI

@Suite("Web search draft reconciliation")
struct WebSearchDraftRebaseTests {
    @Test("Pending state carries only a credential-presence flag")
    func secretFreePendingState() {
        let saved = WebSearchConfiguration(provider: .tavily)
        var draft = WebSearchDraft(configuration: saved)
        #expect(draft.pending.matches(saved))
        draft.credential = "  synthetic-key  "
        #expect(draft.pending == WebSearchPendingSettings(configuration: saved, hasTypedCredential: true))
        #expect(!draft.pending.matches(saved))
        let restored = WebSearchDraft(configuration: saved, pending: draft.pending)
        #expect(restored.credential.isEmpty)
        #expect(restored.pending.matches(saved))
        draft.credential = " \n "
        #expect(draft.pending.matches(saved))
    }

    @Test("Rebasing takes untouched fields and preserves edited limits and the active credential")
    func rebasePreservesEdits() {
        let saved = WebSearchConfiguration(provider: .tavily, resultsLimit: 10, maximumUses: 3)
        var draft = WebSearchDraft(configuration: saved)
        draft.credential = "synthetic-key"
        draft.maximumUses = 7
        let applied = WebSearchConfiguration(provider: .tavily, resultsLimit: 12, maximumUses: 5)

        draft.rebase(on: applied, replacing: saved)

        #expect(
            draft.input.configuration == WebSearchConfiguration(provider: .tavily, resultsLimit: 12, maximumUses: 7))
        #expect(draft.credential == "synthetic-key")
    }

    @Test("A newly applied provider drops the old provider's key and clamps an edited limit")
    func rebaseSwitchesProvider() {
        let saved = WebSearchConfiguration(provider: .firecrawl, resultsLimit: 40)
        var draft = WebSearchDraft(configuration: saved)
        draft.credential = "synthetic-key"
        draft.resultsLimit = 80

        draft.rebase(on: .init(provider: .tavily, resultsLimit: 10, maximumUses: 5), replacing: saved)

        #expect(
            draft.input.configuration == WebSearchConfiguration(provider: .tavily, resultsLimit: 20, maximumUses: 5))
        #expect(draft.credential.isEmpty)
    }

    @Test("A user-selected provider is not replaced by an unrelated applied snapshot")
    func rebasePreservesSelectedProvider() {
        let saved = WebSearchConfiguration(provider: .firecrawl)
        var draft = WebSearchDraft(configuration: saved)
        draft.select(provider: .tavily)
        draft.credential = "synthetic-key"

        draft.rebase(on: .init(provider: .brave), replacing: saved)

        #expect(draft.provider == .tavily)
        #expect(draft.credential == "synthetic-key")
    }
}
