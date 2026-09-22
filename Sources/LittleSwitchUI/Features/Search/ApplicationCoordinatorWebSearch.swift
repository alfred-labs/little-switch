import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchSearch

extension ApplicationCoordinator {
    /// Records web search edits without writing them. The draft outlives the
    /// pane, so navigating away no longer discards typed settings, and the
    /// Apply button can report whether anything is waiting.
    public func setWebSearchDraft(_ input: WebSearchPendingSettings?) async -> CoordinatorSnapshot {
        pendingWebSearchSettings = input.flatMap { draft in
            draft.matches(configuration.webSearch) ? nil : draft
        }
        webSearchDraftRevision &+= 1
        return await snapshot()
    }

    public func saveWebSearch(_ input: WebSearchInput) async throws -> CoordinatorSnapshot {
        let normalized: WebSearchConfiguration
        do {
            normalized = try input.configuration.normalized()
        } catch {
            throw Error.invalidWebSearchConfiguration
        }

        let provider = normalized.provider
        let previousConfiguration = configuration
        let previousSecret = try secretStore.read(account: .webSearch(provider))
        let trimmed = input.credential?.trimmingCharacters(in: .whitespacesAndNewlines)
        let proposedSecret = trimmed.flatMap { $0.isEmpty ? nil : $0 }
        let policy = Self.credentialPolicy(provider: provider)
        if case .required(let missingCredential) = policy, proposedSecret == nil, previousSecret == nil {
            throw missingCredential
        }

        configuration.webSearch = normalized
        var credentialWasMutated = false
        do {
            if let proposedSecret, provider != .disabled {
                try secretStore.write(proposedSecret, account: .webSearch(provider))
                credentialWasMutated = true
            }
        } catch {
            configuration = previousConfiguration
            throw error
        }
        do {
            try configurationStore.save(configuration)
        } catch {
            let transactionError = error
            configuration = previousConfiguration
            guard credentialWasMutated else {
                throw transactionError
            }
            do {
                try restoreWebSearchCredential(previousSecret, provider: provider)
            } catch {
                throw Error.rollbackFailed
            }
            throw transactionError
        }
        pendingWebSearchSettings = nil
        webSearchDraftRevision &+= 1
        await replaceGatewayRoutingIfNeeded()
        return await snapshot()
    }

    /// What applying a configuration demands of its stored credential. One
    /// exhaustive switch per provider: a new provider cannot compile without
    /// deciding whether its key is required or optional, and which error a
    /// missing one reports.
    private enum WebSearchCredentialPolicy {
        case required(ApplicationCoordinator.Error)
        case optional
    }

    private static func credentialPolicy(
        provider: WebSearchProvider
    ) -> WebSearchCredentialPolicy {
        switch provider {
        case .tavily:
            .required(.missingTavilyCredential)
        case .brave:
            .required(.missingBraveCredential)
        case .exa:
            .required(.missingExaCredential)
        case .firecrawl:
            .required(.missingFirecrawlCredential)
        case .disabled:
            .optional
        }
    }

    private func restoreWebSearchCredential(
        _ secret: String?,
        provider: WebSearchProvider
    ) throws {
        if let secret {
            try secretStore.write(secret, account: .webSearch(provider))
        } else {
            try secretStore.delete(account: .webSearch(provider))
        }
    }
}
