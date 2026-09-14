import Foundation
import LittleSwitchCommon
import NIOHTTP1
import Testing

@testable import LittleSwitchSearch

@Suite("Shared search adapter contract")
struct WebSearchContractTests {
    @Test("Every adapter returns the same validated result values", arguments: SearchAdapterFixture.allCases)
    func normalizedResults(adapter: SearchAdapterFixture) async throws {
        let transport = SearchRecordingTransport(responses: [searchResponse(body: try adapter.response())])
        let results = try await WebSearchClientFactory.make(configuration: adapter.configuration, transport: transport)
            .search(
                query: "Swift", configuration: adapter.configuration, credential: "synthetic-key", options: .init())
        #expect(results == [.init(title: "Swift", url: "https://swift.org/", content: "Documentation")])
        #expect(await transport.requests.count == 1)
    }

    @Test("Missing credentials fail before any network request", arguments: SearchAdapterFixture.allCases)
    func missingCredentials(adapter: SearchAdapterFixture) async {
        let transport = SearchRecordingTransport(responses: [])
        await #expect(throws: WebSearchProviderError.missingCredential) {
            try await WebSearchClientFactory.make(configuration: adapter.configuration, transport: transport).search(
                query: "Swift", configuration: adapter.configuration, credential: " \n\t", options: .init())
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("HTTP failures expose only common errors", arguments: SearchAdapterFixture.allCases, [401, 403, 429, 503])
    func statusErrors(adapter: SearchAdapterFixture, status: Int) async {
        let expected: WebSearchProviderError =
            switch status {
            case 401, 403: .unauthorized
            case 429: .rateLimited
            default: .httpStatus(status)
            }
        let transport = SearchRecordingTransport(responses: [
            searchResponse(status: HTTPResponseStatus(statusCode: status), body: "private response detail")
        ])
        await #expect(throws: expected) {
            try await WebSearchClientFactory.make(configuration: adapter.configuration, transport: transport).search(
                query: "Swift", configuration: adapter.configuration, credential: "synthetic-key", options: .init())
        }
    }

    @Test("Cancellation crosses every adapter unchanged", arguments: SearchAdapterFixture.allCases)
    func cancellation(adapter: SearchAdapterFixture) async {
        let client = WebSearchClientFactory.make(
            configuration: adapter.configuration, transport: SearchFailingTransport(error: .cancelled))
        await #expect(throws: CancellationError.self) {
            try await client.search(
                query: "Swift", configuration: adapter.configuration, credential: "synthetic-key", options: .init())
        }
    }

    @Test("Each provider's result limit is enforced before transport", arguments: SearchAdapterFixture.allCases)
    func limits(adapter: SearchAdapterFixture) async {
        let transport = SearchRecordingTransport(responses: [])
        let configuration = WebSearchConfiguration(
            provider: adapter.provider, resultsLimit: adapter.provider.resultsLimitRange.upperBound + 1)
        await #expect(throws: WebSearchConfiguration.Error.invalidResultsLimit) {
            try await WebSearchClientFactory.make(configuration: configuration, transport: transport).search(
                query: "Swift", configuration: configuration, credential: "synthetic-key", options: .init())
        }
        #expect(await transport.requests.isEmpty)
    }
}

enum SearchAdapterFixture: CaseIterable, Sendable {
    case firecrawl, tavily, brave, exa

    var provider: WebSearchProvider {
        switch self {
        case .firecrawl: .firecrawl
        case .tavily: .tavily
        case .brave: .brave
        case .exa: .exa
        }
    }

    var configuration: WebSearchConfiguration { .init(provider: provider) }

    func response() throws -> String {
        let results: [[String: Any]] = [
            hit(title: " Swift ", url: " https://swift.org/ "),
            hit(title: " ", url: "https://invalid.example/"),
            hit(title: "Unsafe", url: "file:///private/tmp/page"),
        ]
        let envelope: [String: Any] =
            switch self {
            case .firecrawl: ["success": true, "data": ["web": results]]
            case .tavily, .exa: ["results": results]
            case .brave: ["type": "search", "web": ["results": results]]
            }
        return try #require(String(data: JSONSerialization.data(withJSONObject: envelope), encoding: .utf8))
    }

    private func hit(title: String, url: String) -> [String: Any] {
        var hit: [String: Any] = ["title": title, "url": url]
        switch self {
        case .firecrawl: hit["markdown"] = "Documentation"
        case .tavily: hit["content"] = "Documentation"
        case .brave: hit["description"] = "Documentation"
        case .exa: hit["highlights"] = ["Documentation"]
        }
        return hit
    }
}
