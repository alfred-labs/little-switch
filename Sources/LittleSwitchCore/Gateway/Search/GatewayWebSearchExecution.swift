import Foundation
import LittleSwitchSearch

package struct WebSearchAttempt {
    let results: [WebSearchResult]?
    let failure: (any Error)?

    package init(results: [WebSearchResult]?, failure: (any Error)?) {
        self.results = results
        self.failure = failure
    }
}

/// One decided search attempt, shared by every orchestration loop: the
/// empty-query / budget / execution-failure ladder is evaluated here once,
/// and each protocol surface maps the outcome onto its own error codes and
/// follow-up plumbing.
package enum WebSearchAttemptOutcome {
    case invalidRequest
    case overBudget
    case unavailable
    case results([WebSearchResult])
}

/// What a loop asks of one search admission: the raw tool query, the
/// request's filter options, and the budget the loop enforces.
package struct WebSearchAttemptRequest: Sendable {
    let rawQuery: String
    let options: WebSearchFilterOptions
    let successfulSearches: Int
    let maximumUses: Int

    package init(
        rawQuery: String,
        options: WebSearchFilterOptions,
        successfulSearches: Int,
        maximumUses: Int
    ) {
        self.rawQuery = rawQuery
        self.options = options
        self.successfulSearches = successfulSearches
        self.maximumUses = maximumUses
    }
}

extension GatewayResponder {
    /// The active search provider's stored credential. Both wire surfaces
    /// read through here so the account choice is made once — the hardcoded
    /// provider bug this replaces had to be fixed in each copy separately.
    func webSearchCredential(
        for configuration: WebSearchConfiguration
    ) throws -> String? {
        try secretStore.read(account: .webSearch(configuration.provider))
    }

    /// Decides and, when admitted, runs one search. Only cancellation
    /// propagates; every other rejection comes back as an outcome for the
    /// caller to name in its own wire vocabulary.
    package func admittedWebSearch(
        _ request: WebSearchAttemptRequest,
        configuration: WebSearchConfiguration,
        credential: String?,
        eventID: UUID
    ) async throws -> WebSearchAttemptOutcome {
        guard !request.rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .invalidRequest
        }
        guard request.successfulSearches < request.maximumUses else {
            return .overBudget
        }
        let attempt = try await executeWebSearch(
            query: request.rawQuery,
            configuration: configuration,
            credential: credential,
            options: request.options,
            eventID: eventID
        )
        guard let results = attempt.results else {
            return .unavailable
        }
        return .results(results)
    }
    /// Executes one provider search through the shared factory and records
    /// the attempt against the client request's event. Only cancellation
    /// propagates; any other failure comes back as `failure` so each
    /// protocol keeps its own follow-up turn and trace points.
    package func executeWebSearch(
        query: String,
        configuration: WebSearchConfiguration,
        credential: String?,
        options: WebSearchFilterOptions,
        eventID: UUID
    ) async throws -> WebSearchAttempt {
        let searchStartedAt = Date()
        var didStart = false
        do {
            try Task.checkCancellation()
            let client = WebSearchClientFactory.make(
                configuration: configuration,
                transport: transport
            )
            didStart = true
            await GatewayMonitoringScope.current?.searched()
            let results = try await client.search(
                query: query,
                configuration: configuration,
                credential: credential,
                options: options
            )
            try Task.checkCancellation()
            await monitoring?.store.recordWebSearch(provider: configuration.provider, outcome: .success)
            recordWebSearch(
                eventID: eventID,
                search: .make(
                    configuration: configuration,
                    query: query,
                    startedAt: searchStartedAt,
                    resultCount: results.count,
                    error: nil
                )
            )
            return WebSearchAttempt(results: results, failure: nil)
        } catch is CancellationError {
            if didStart {
                await monitoring?.store.recordWebSearch(provider: configuration.provider, outcome: .cancelled)
            }
            throw CancellationError()
        } catch {
            if didStart { await monitoring?.store.recordWebSearch(provider: configuration.provider, outcome: .failure) }
            recordWebSearch(
                eventID: eventID,
                search: .make(
                    configuration: configuration,
                    query: query,
                    startedAt: searchStartedAt,
                    resultCount: nil,
                    error: error
                )
            )
            return WebSearchAttempt(results: nil, failure: error)
        }
    }
}
