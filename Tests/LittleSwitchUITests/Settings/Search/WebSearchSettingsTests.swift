import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchSearch
import Testing

@testable import LittleSwitchUI

@Suite("Web search settings")
struct WebSearchSettingsTests {
    @Test("Drafts mirror saved settings without exposing credentials")
    func draftFromConfiguration() {
        let draft = WebSearchDraft(
            configuration: WebSearchConfiguration(
                provider: .firecrawl,
                resultsLimit: 42,
                maximumUses: 7
            )
        )

        #expect(draft.provider == .firecrawl)
        #expect(draft.resultsLimit == 42)
        #expect(draft.maximumUses == 7)
        #expect(draft.credential.isEmpty)
    }

    @Test("Cloud uses the fixed endpoint and omits an empty credential")
    func cloudInput() {
        var draft = WebSearchDraft(configuration: .disabled)
        draft.provider = .firecrawl
        draft.credential = " \n\t "

        let input = draft.input

        #expect(input.credential == nil)
    }

    @Test("Tavily drafts clamp the result limit")
    func tavilyDraft() {
        var draft = WebSearchDraft(configuration: .firecrawlCloud)
        draft.resultsLimit = 100

        draft.select(provider: .tavily)

        #expect(draft.resultsLimit == 20)
        #expect(draft.input.configuration.resultsLimit == 20)
    }

    @Test("Tavily credential hints state the key is required")
    func tavilyCredentialPresentation() {
        var draft = WebSearchDraft(configuration: .disabled)
        draft.select(provider: .tavily)

        #expect(
            draft.credentialPresentation.accessibilityHint
                == L10n.resource("Required for Tavily. Leave blank to keep the saved key.")
        )
        #expect(draft.credentialPresentation.placeholder == L10n.resource("Leave blank to keep the saved key"))
    }

    @Test("A typed Tavily key reaches the input trimmed")
    func tavilyCredentialInput() {
        var draft = WebSearchDraft(configuration: .disabled)
        draft.select(provider: .tavily)
        draft.credential = " \ntvly-key\t "

        #expect(draft.input.credential == "tvly-key")
    }

    @Test("Brave drafts clamp the result limit")
    func braveDraft() {
        var draft = WebSearchDraft(configuration: .firecrawlCloud)
        draft.resultsLimit = 100

        draft.select(provider: .brave)

        #expect(draft.resultsLimit == 20)
        #expect(draft.input.configuration.resultsLimit == 20)
    }

    @Test("Brave credential hints state the key is required")
    func braveCredentialPresentation() {
        var draft = WebSearchDraft(configuration: .disabled)
        draft.select(provider: .brave)

        #expect(
            draft.credentialPresentation.accessibilityHint
                == L10n.resource("Required for Brave. Leave blank to keep the saved key.")
        )
        #expect(draft.credentialPresentation.placeholder == L10n.resource("Leave blank to keep the saved key"))
    }

    @Test("A typed Brave key reaches the input trimmed")
    func braveCredentialInput() {
        var draft = WebSearchDraft(configuration: .disabled)
        draft.select(provider: .brave)
        draft.credential = " \nbrave-key\t "

        #expect(draft.input.credential == "brave-key")
    }

    @Test("Switching providers drops the typed credential")
    func providerSwitchDropsCredential() {
        var draft = WebSearchDraft(configuration: .firecrawlCloud)
        draft.credential = "fc-key"

        draft.select(provider: .tavily)

        // The typed key belongs to the provider whose field it was entered
        // in: carrying it over would silently write it under the other
        // provider's keychain account and clobber its saved key.
        #expect(draft.credential.isEmpty)
        #expect(draft.input.credential == nil)
    }

    @Test("Re-tapping the active provider keeps the typed credential")
    func providerReTapKeepsCredential() {
        var draft = WebSearchDraft(configuration: .firecrawlCloud)
        draft.credential = "fc-key"
        draft.resultsLimit = 42

        draft.select(provider: .firecrawl)

        #expect(draft.credential == "fc-key")
        #expect(draft.resultsLimit == 42)
    }

    @Test("Usage controls keep Firecrawl's supported ranges")
    func limits() {
        #expect(WebSearchProvider.firecrawl.resultsLimitRange == 1...100)
        #expect(WebSearchProvider.tavily.resultsLimitRange == 1...20)
        #expect(WebSearchProvider.brave.resultsLimitRange == 1...20)
        #expect(WebSearchDraft.maximumUsesRange == 1...10)
        let draft = WebSearchDraft(configuration: .firecrawlCloud)
        #expect(draft.resultsLimit == 10)
        #expect(draft.maximumUses == 3)
    }

    @Test("The credential section names the provider and is absent when disabled")
    func connectionTitles() {
        var draft = WebSearchDraft(configuration: .disabled)
        #expect(draft.connectionTitle == nil)

        draft.select(provider: .firecrawl)
        #expect(draft.connectionTitle == L10n.resource("Firecrawl connection"))

        draft.select(provider: .tavily)
        #expect(draft.connectionTitle == L10n.resource("Tavily connection"))

        draft.select(provider: .brave)
        #expect(draft.connectionTitle == L10n.resource("Brave connection"))
    }

    @Test("Credential guidance explains whether blank input preserves or removes the key")
    func credentialGuidance() {
        var draft = WebSearchDraft(configuration: .firecrawlCloud)

        #expect(draft.credentialPresentation.placeholder == L10n.resource("Leave blank to keep the saved key"))
        #expect(
            draft.credentialPresentation.accessibilityHint
                == L10n.resource("Required for Firecrawl. Leave blank to keep the saved key.")
        )

        draft.select(provider: .tavily)
        #expect(draft.credentialPresentation.placeholder == L10n.resource("Leave blank to keep the saved key"))
        #expect(
            draft.credentialPresentation.accessibilityHint
                == L10n.resource("Required for Tavily. Leave blank to keep the saved key.")
        )

        draft.select(provider: .brave)
        #expect(draft.credentialPresentation.placeholder == L10n.resource("Leave blank to keep the saved key"))
        #expect(
            draft.credentialPresentation.accessibilityHint
                == L10n.resource("Required for Brave. Leave blank to keep the saved key.")
        )
    }
}
