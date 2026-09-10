import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

public struct FirecrawlSearchClient: WebSearchSearching, Sendable {
    private let transport: any UpstreamTransport
    private let maximumResponseBytes: Int
    private let maximumContentBytes: Int

    public init(
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
        options: WebSearchFilterOptions = WebSearchFilterOptions()
    ) async throws -> [WebSearchResult] {
        let configuration = try configuration.normalized()
        guard configuration.provider == .firecrawl else {
            throw WebSearchProviderError.invalidResponse
        }

        let credential = try WebSearchTransport.requiredCredential(credential)

        var request = try WebSearchTransport.request(
            path: "/search",
            configuration: configuration,
            bearer: credential
        )
        request.body = .bytes(
            try JSONEncoder().encode(
                SearchRequest(
                    query: query,
                    limit: configuration.resultsLimit,
                    sources: [.init(type: "web")],
                    includeDomains: options.includeDomains,
                    excludeDomains: options.excludeDomains,
                    location: options.location,
                    country: options.country
                )
            )
        )

        let data = try await WebSearchTransport.responseBody(
            request,
            transport: transport,
            maximumResponseBytes: maximumResponseBytes
        )
        let envelope = try WebSearchTransport.decodeEnvelope(SearchEnvelope.self, from: data)
        guard envelope.success, let hits = envelope.data?.web else {
            throw WebSearchProviderError.invalidResponse
        }
        let valid = hits.compactMap { hit in
            WebSearchResultShaping.validated(
                title: hit.title,
                url: hit.url,
                content: hit.description ?? hit.markdown ?? ""
            )
        }
        return WebSearchResultShaping.bounded(
            valid,
            limit: configuration.resultsLimit,
            maximumContentBytes: maximumContentBytes
        )
    }
}

extension FirecrawlSearchClient {
    fileprivate struct SearchRequest: Encodable {
        let query: String
        let limit: Int
        let sources: [SearchSource]
        let includeDomains: [String]?
        let excludeDomains: [String]?
        let location: String?
        let country: String?
    }

    fileprivate struct SearchSource: Encodable {
        let type: String
    }

    fileprivate struct SearchEnvelope: Decodable {
        let success: Bool
        let data: SearchData?
    }

    fileprivate struct SearchData: Decodable {
        let web: [SearchHit]?
    }

    fileprivate struct SearchHit: Decodable {
        let title: String?
        let url: String?
        let description: String?
        let markdown: String?
    }
}
