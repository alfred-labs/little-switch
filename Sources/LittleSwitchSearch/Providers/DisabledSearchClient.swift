/// The disabled configuration's client. Search loops reject disabled
/// configurations before reaching a client, so this exists to keep the
/// factory's switch total without borrowing a real provider's adapter and
/// its mismatch guard; if it is ever called it fails plainly unavailable,
/// without touching the transport.
package struct DisabledSearchClient: WebSearchSearching {
    package init() {}

    package func search(
        query: String,
        configuration: WebSearchConfiguration,
        credential: String?,
        options: WebSearchFilterOptions
    ) async throws -> [WebSearchResult] {
        throw WebSearchProviderError.unavailable
    }
}
