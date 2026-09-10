import Foundation
import LittleSwitchTransport

package struct ExaSearchClient: WebSearchSearching, Sendable {
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
        guard configuration.provider == .exa else {
            throw WebSearchProviderError.invalidResponse
        }
        let credential = try WebSearchTransport.requiredCredential(credential)
        var request = try WebSearchTransport.request(
            path: "/search", configuration: configuration, bearer: nil
        )
        request.headers.replaceOrAdd(name: "x-api-key", value: credential)
        request.body = .bytes(
            try JSONEncoder().encode(
                SearchRequest(
                    query: query,
                    numResults: configuration.resultsLimit,
                    includeDomains: options.includeDomains,
                    excludeDomains: options.excludeDomains,
                    // Exa accepts an ISO country code, but no city/region hint.
                    userLocation: options.country
                )
            )
        )

        let data = try await WebSearchTransport.responseBody(
            request, transport: transport, maximumResponseBytes: maximumResponseBytes
        )
        let envelope = try WebSearchTransport.decodeEnvelope(SearchEnvelope.self, from: data)
        guard let hits = envelope.results else {
            throw WebSearchProviderError.invalidResponse
        }
        let results = hits.compactMap { hit in
            WebSearchResultShaping.validated(
                title: hit.title,
                url: hit.url,
                content: hit.highlights?.joined(separator: "\n") ?? ""
            )
        }
        return WebSearchResultShaping.bounded(
            results, limit: configuration.resultsLimit, maximumContentBytes: maximumContentBytes
        )
    }
}

extension ExaSearchClient {
    fileprivate struct SearchRequest: Encodable {
        let query: String
        let numResults: Int
        let includeDomains: [String]?
        let excludeDomains: [String]?
        let userLocation: String?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(query, forKey: .query)
            try container.encode("auto", forKey: .type)
            try container.encode(numResults, forKey: .numResults)
            try container.encodeIfPresent(includeDomains, forKey: .includeDomains)
            try container.encodeIfPresent(excludeDomains, forKey: .excludeDomains)
            try container.encodeIfPresent(userLocation, forKey: .userLocation)
            var contents = container.nestedContainer(keyedBy: ContentKeys.self, forKey: .contents)
            try contents.encode(false, forKey: .text)
            var highlights = contents.nestedContainer(keyedBy: HighlightKeys.self, forKey: .highlights)
            try highlights.encode(4_000, forKey: .maxCharacters)
        }

        private enum CodingKeys: String, CodingKey {
            case query, type, numResults, includeDomains, excludeDomains, userLocation, contents
        }

        private enum ContentKeys: String, CodingKey {
            case text, highlights
        }

        private enum HighlightKeys: String, CodingKey {
            case maxCharacters
        }
    }

    fileprivate struct SearchEnvelope: Decodable {
        let results: [SearchHit]?
    }

    fileprivate struct SearchHit: Decodable {
        let title: String?
        let url: String?
        let highlights: [String]?
    }
}
