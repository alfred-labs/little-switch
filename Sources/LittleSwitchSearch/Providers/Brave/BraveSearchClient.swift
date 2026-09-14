import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

package struct BraveSearchClient: WebSearchSearching, Sendable {
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
        guard configuration.provider == .brave else {
            throw WebSearchProviderError.invalidResponse
        }

        let credential = try WebSearchTransport.requiredCredential(credential)

        // Normalization validates the persisted limit against the
        // provider's own range, so nothing over the ceiling gets this far.
        // Brave's API has no domain filters and no approximate-location
        // equivalent: both are knowingly dropped here (documented in
        // known-limitations.md) while the country filter maps to its
        // native parameter.
        let resultLimit = configuration.resultsLimit
        var query = [("q", query), ("count", String(resultLimit))]
        if let country = options.country {
            query.append(("country", country))
        }
        let request = try WebSearchTransport.getRequest(
            path: "/res/v1/web/search",
            query: query,
            configuration: configuration,
            subscriptionToken: credential
        )

        let data = try await WebSearchTransport.responseBody(
            request,
            transport: transport,
            maximumResponseBytes: maximumResponseBytes
        )
        let envelope = try WebSearchTransport.decodeEnvelope(SearchEnvelope.self, from: data)
        // Brave stamps every web-search answer with "type": "search", so
        // requiring it separates a genuinely empty result set (the web
        // section may be absent) from a 200 body that is not a search
        // answer at all, which would otherwise read as zero results.
        guard envelope.type == "search" else {
            throw WebSearchProviderError.invalidResponse
        }
        let hits = envelope.web?.results ?? []
        let results = hits.compactMap { hit in
            WebSearchResultShaping.validated(
                title: hit.title,
                url: hit.url,
                content: hit.description ?? ""
            )
        }
        return WebSearchResultShaping.bounded(
            results,
            limit: resultLimit,
            maximumContentBytes: maximumContentBytes
        )
    }
}

extension BraveSearchClient {
    fileprivate struct SearchEnvelope: Decodable {
        let type: String?
        let web: WebSection?
    }

    fileprivate struct WebSection: Decodable {
        let results: [SearchHit]?
    }

    fileprivate struct SearchHit: Decodable {
        let title: String?
        let url: String?
        let description: String?
    }
}
