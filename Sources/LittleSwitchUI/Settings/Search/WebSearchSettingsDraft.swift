import Foundation
import LittleSwitchCommon
import LittleSwitchSearch

struct WebSearchCredentialPresentation: Equatable, Sendable {
    let placeholder: LocalizedStringResource
    let accessibilityHint: LocalizedStringResource
}

struct WebSearchDraft: Equatable {
    static let maximumUsesRange = 1...10

    var provider: WebSearchProvider
    var credential = ""
    var resultsLimit: Int
    var maximumUses: Int

    init(configuration: WebSearchConfiguration) {
        provider = configuration.provider
        resultsLimit = configuration.resultsLimit
        maximumUses = configuration.maximumUses
    }

    /// Restores edits that were left waiting when the pane was last closed.
    /// A typed credential is deliberately not carried across: the field says
    /// blank keeps the saved key, and a secret should not linger unseen.
    init(configuration: WebSearchConfiguration, pending: WebSearchInput?) {
        self.init(configuration: pending?.configuration ?? configuration)
    }

    var resultsRange: ClosedRange<Int> {
        provider.resultsLimitRange
    }

    /// The credential section is hidden while search is disabled.
    var connectionTitle: LocalizedStringResource? {
        switch provider {
        case .disabled:
            nil
        case .firecrawl:
            L10n.resource("Firecrawl connection")
        case .tavily:
            L10n.resource("Tavily connection")
        case .brave:
            L10n.resource("Brave connection")
        case .exa:
            L10n.resource("Exa connection")
        }
    }

    /// Central point for provider switches so the persisted limit always
    /// lands inside the newly selected provider's API range. A typed
    /// credential is dropped with the same hygiene as pane close: it belongs
    /// to the provider whose field it was entered in, and carrying it over
    /// would write one provider's key under the other's keychain account.
    /// Re-tapping the active provider is a no-op — there is no account
    /// change to protect against, and clearing would lose the typing.
    mutating func select(provider newProvider: WebSearchProvider) {
        guard newProvider != provider else {
            return
        }
        provider = newProvider
        credential = ""
        let range = resultsRange
        resultsLimit = min(max(resultsLimit, range.lowerBound), range.upperBound)
    }

    var input: WebSearchInput {
        WebSearchInput(
            configuration: WebSearchConfiguration(
                provider: provider,
                resultsLimit: resultsLimit,
                maximumUses: maximumUses
            ),
            credential: trimmedCredential.isEmpty ? nil : trimmedCredential
        )
    }

    var credentialPresentation: WebSearchCredentialPresentation {
        switch provider {
        case .tavily:
            WebSearchCredentialPresentation(
                placeholder: L10n.resource("Leave blank to keep the saved key"),
                accessibilityHint:
                    L10n.resource("Required for Tavily. Leave blank to keep the saved key.")
            )
        case .brave:
            WebSearchCredentialPresentation(
                placeholder: L10n.resource("Leave blank to keep the saved key"),
                accessibilityHint:
                    L10n.resource("Required for Brave. Leave blank to keep the saved key.")
            )
        case .exa:
            WebSearchCredentialPresentation(
                placeholder: L10n.resource("Leave blank to keep the saved key"),
                accessibilityHint:
                    L10n.resource("Required for Exa. Leave blank to keep the saved key.")
            )
        case .firecrawl, .disabled:
            WebSearchCredentialPresentation(
                placeholder: L10n.resource("Leave blank to keep the saved key"),
                accessibilityHint:
                    L10n.resource(
                        "Required for Firecrawl. Leave blank to keep the saved key."
                    )
            )
        }
    }

    private var trimmedCredential: String {
        credential.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
