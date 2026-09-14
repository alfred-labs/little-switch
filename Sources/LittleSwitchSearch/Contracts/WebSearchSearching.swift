import LittleSwitchCommon

/// A search provider client. The gateway owns one concrete client per
/// configured provider and dispatches on the configuration.
package protocol WebSearchSearching: Sendable {
    func search(
        query: String,
        configuration: WebSearchConfiguration,
        credential: String?,
        options: WebSearchFilterOptions
    ) async throws -> [WebSearchResult]
}
