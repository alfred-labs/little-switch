import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

package struct TavilySearchClient: WebSearchSearching, Sendable {
    private let transport: any UpstreamTransport
    private let maximumResponseBytes: Int
    private let maximumContentBytes: Int

    package init(
        transport: any UpstreamTransport,
        maximumResponseBytes: Int = 8 * 1_024 * 1_024,
        maximumContentBytes: Int = 256 * 1_024
    ) {
        self.transport = transport
        self.maximumResponseBytes = maximumResponseBytes
        self.maximumContentBytes = max(0, maximumContentBytes)
    }

    package func search(
        query: String,
        configuration: WebSearchConfiguration,
        credential: String?,
        options: WebSearchFilterOptions
    ) async throws -> [WebSearchResult] {
        let configuration = try configuration.normalized()
        guard configuration.provider == .tavily else {
            throw WebSearchProviderError.invalidResponse
        }

        let credential = try WebSearchTransport.requiredCredential(credential)

        // Normalization validates the persisted limit against the
        // provider's own range, so nothing over the ceiling gets this far.
        let resultLimit = configuration.resultsLimit
        var request = try WebSearchTransport.request(
            path: "/search",
            configuration: configuration,
            bearer: credential
        )
        request.body = .bytes(
            try JSONEncoder().encode(
                // Tavily's search API has no geographic parameters: a
                // request's user_location filter is knowingly dropped here
                // (documented in known-limitations.md) rather than sent
                // where it would be rejected or silently reinterpreted.
                SearchRequest(
                    query: query,
                    maxResults: resultLimit,
                    includeDomains: options.includeDomains,
                    excludeDomains: options.excludeDomains
                )
            )
        )

        let data = try await WebSearchTransport.responseBody(
            request,
            transport: transport,
            maximumResponseBytes: maximumResponseBytes,
            rateLimitedStatuses: [429, 432, 433]
        )
        let envelope = try WebSearchTransport.decodeEnvelope(SearchEnvelope.self, from: data)
        guard let hits = envelope.results else {
            throw WebSearchProviderError.invalidResponse
        }
        let results = hits.compactMap { hit in
            WebSearchResultShaping.validated(
                title: hit.title,
                url: hit.url,
                content: hit.content ?? ""
            )
        }
        return WebSearchResultShaping.bounded(
            results,
            limit: resultLimit,
            maximumContentBytes: maximumContentBytes
        )
    }
}

extension TavilySearchClient {
    fileprivate struct SearchRequest: Encodable {
        let query: String
        let maxResults: Int
        let includeDomains: [String]?
        let excludeDomains: [String]?

        enum CodingKeys: String, CodingKey {
            case query
            case maxResults = "max_results"
            case includeDomains = "include_domains"
            case excludeDomains = "exclude_domains"
        }
    }

    fileprivate struct SearchEnvelope: Decodable {
        let results: [SearchHit]?
    }

    fileprivate struct SearchHit: Decodable {
        let title: String?
        let url: String?
        let content: String?
    }
}
