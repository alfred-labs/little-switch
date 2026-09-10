import AsyncHTTPClient
import Foundation
import NIOHTTP1
import Testing

@testable import LittleSwitchSearch

@Suite("Exa search client")
struct ExaSearchClientTests {
    @Test("Exa sends an authenticated search with bounded highlights")
    func searchRequest() async throws {
        let provider = try #require(WebSearchProvider(rawValue: "exa"))
        let configuration = WebSearchConfiguration(provider: provider)
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: #"{"results":[]}"#)
        ])
        let client = WebSearchClientFactory.make(configuration: configuration, transport: transport)

        let results = try await client.search(
            query: "current Swift release",
            configuration: configuration,
            credential: "  exa-test-key\n",
            options: WebSearchFilterOptions()
        )

        #expect(results.isEmpty)
        let request = try #require(await transport.requests.first)
        #expect(request.url == "https://api.exa.ai/search")
        #expect(request.method == .POST)
        #expect(request.headers["x-api-key"] == ["exa-test-key"])
        #expect(request.headers["authorization"].isEmpty)
        #expect(request.headers["content-type"] == ["application/json"])
        #expect(request.headers["accept"] == ["application/json"])
        let object = try JSONSerialization.jsonObject(with: request.body) as? NSDictionary
        #expect(
            object == [
                "query": "current Swift release",
                "type": "auto",
                "numResults": 10,
                "contents": ["text": false, "highlights": ["maxCharacters": 4_000]],
            ] as NSDictionary
        )
    }

    @Test("Exa forwards native domains and country without inventing city support")
    func filters() async throws {
        let transport = SearchRecordingTransport(responses: [searchResponse(body: #"{"results":[]}"#)])
        _ = try await ExaSearchClient(transport: transport).search(
            query: "Swift events",
            configuration: WebSearchConfiguration(provider: .exa, resultsLimit: 100),
            credential: "test-key",
            options: WebSearchFilterOptions(
                includeDomains: ["swift.org", "github.com"],
                excludeDomains: ["example.com"],
                location: "Paris, Ile-de-France",
                country: "FR"
            )
        )
        let request = try #require(await transport.requests.first)
        let object = try JSONSerialization.jsonObject(with: request.body) as? NSDictionary
        #expect(
            object == [
                "query": "Swift events", "type": "auto", "numResults": 100,
                "contents": ["text": false, "highlights": ["maxCharacters": 4_000]],
                "includeDomains": ["swift.org", "github.com"],
                "excludeDomains": ["example.com"], "userLocation": "FR",
            ] as NSDictionary
        )
    }

    @Test("Exa joins highlights and skips hits without valid titles or public web URLs")
    func resultParsing() async throws {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(
                body: #"""
                    {"results":[
                      {"title":" Swift.org ","url":" https://swift.org/ ","highlights":["First","Second"],
                       "text":"Full page must not reach model","summary":"Not requested"},
                      {"title":"No highlights","url":"https://example.org/"},
                      {"title":"Empty highlights","url":"http://example.org/empty","highlights":[]},
                      {"title":"","url":"https://invalid.example"},
                      {"url":"https://missing-title.example"},
                      {"title":"Missing URL"},
                      {"title":"Invalid scheme","url":"file:///tmp/test"},
                      {"title":"Credentials","url":"https://user:password@example.org"}
                    ],"requestId":"ignored"}
                    """#
            )
        ])
        let results = try await ExaSearchClient(transport: transport).search(
            query: "Swift",
            configuration: WebSearchConfiguration(provider: .exa),
            credential: "test-key",
            options: WebSearchFilterOptions()
        )
        #expect(
            results == [
                WebSearchResult(
                    title: "Swift.org",
                    url: "https://swift.org/",
                    content: "First\nSecond"),
                WebSearchResult(
                    title: "No highlights",
                    url: "https://example.org/",
                    content: ""),
                WebSearchResult(
                    title: "Empty highlights",
                    url: "http://example.org/empty",
                    content: ""),
            ])
    }

    @Test("Exa caps both result count and aggregate UTF-8 content", arguments: [0, 20])
    func resultBounds(budget: Int) async throws {
        let hits = (0..<4).map { index in
            [
                "title": "Hit \(index)", "url": "https://example.org/\(index)",
                "highlights": [String(repeating: "é", count: 30)],
            ] as [String: Any]
        }
        let body = try JSONSerialization.data(withJSONObject: ["results": hits])
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: try #require(String(data: body, encoding: .utf8)))
        ])
        let results = try await ExaSearchClient(transport: transport, maximumContentBytes: budget).search(
            query: "Swift",
            configuration: WebSearchConfiguration(provider: .exa, resultsLimit: 2),
            credential: "test-key",
            options: WebSearchFilterOptions()
        )
        #expect(
            results == [
                WebSearchResult(
                    title: "Hit 0",
                    url: "https://example.org/0",
                    content: budget == 0 ? "" : "éééé [truncated]"),
                WebSearchResult(
                    title: "Hit 1",
                    url: "https://example.org/1",
                    content: ""),
            ])
        #expect(results.reduce(0) { $0 + $1.content.utf8.count } <= budget)
    }

    @Test("Exa rejects missing or blank keys before transport", arguments: [nil, "", " \n\t"] as [String?])
    func missingCredential(credential: String?) async {
        let transport = SearchRecordingTransport(responses: [])
        await #expect(throws: WebSearchProviderError.missingCredential) {
            try await ExaSearchClient(transport: transport).search(
                query: "Swift",
                configuration: WebSearchConfiguration(provider: .exa),
                credential: credential,
                options: WebSearchFilterOptions()
            )
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Exa rejects another provider before reading its credential")
    func wrongProvider() async {
        let transport = SearchRecordingTransport(responses: [])
        await #expect(throws: WebSearchProviderError.invalidResponse) {
            try await ExaSearchClient(transport: transport).search(
                query: "Swift",
                configuration: .tavily,
                credential: nil,
                options: WebSearchFilterOptions()
            )
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Exa rejects out-of-range limits before transport", arguments: [0, 101])
    func invalidLimit(limit: Int) async {
        let transport = SearchRecordingTransport(responses: [])
        await #expect(throws: WebSearchConfiguration.Error.invalidResultsLimit) {
            try await ExaSearchClient(transport: transport).search(
                query: "Swift",
                configuration: WebSearchConfiguration(provider: .exa, resultsLimit: limit),
                credential: "test-key",
                options: WebSearchFilterOptions()
            )
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test(
        "Exa normalizes errors without exposing provider response bodies",
        arguments: [
            (401, WebSearchProviderError.unauthorized), (403, .unauthorized),
            (402, .httpStatus(402)), (429, .rateLimited), (500, .httpStatus(500)),
        ])
    func statusErrors(status: Int, expected: WebSearchProviderError) async {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(
                status: HTTPResponseStatus(statusCode: status), body: #"{"error":"private provider detail"}"#)
        ])
        await #expect(throws: expected) {
            try await ExaSearchClient(transport: transport).search(
                query: "Swift",
                configuration: WebSearchConfiguration(provider: .exa),
                credential: "test-key",
                options: WebSearchFilterOptions()
            )
        }
    }

    @Test(
        "Exa requires a valid result envelope",
        arguments: ["{", "{}", #"{"results":null}"#, #"{"results":{}}"#, #"{"results":[{"highlights":"invalid"}]}"#])
    func invalidResponse(body: String) async {
        let transport = SearchRecordingTransport(responses: [searchResponse(body: body)])
        await #expect(throws: WebSearchProviderError.invalidResponse) {
            try await ExaSearchClient(transport: transport).search(
                query: "Swift",
                configuration: WebSearchConfiguration(provider: .exa),
                credential: "test-key",
                options: WebSearchFilterOptions()
            )
        }
    }

    @Test("Exa honors the exact response byte ceiling", arguments: [false, true])
    func responseLimit(oversized: Bool) async throws {
        let body = #"{"results":[]}"#
        let transport = SearchRecordingTransport(responses: [searchResponse(body: body)])
        let client = ExaSearchClient(transport: transport, maximumResponseBytes: body.utf8.count - (oversized ? 1 : 0))
        if oversized {
            await #expect(throws: WebSearchProviderError.responseTooLarge) {
                try await client.search(
                    query: "Swift",
                    configuration: WebSearchConfiguration(provider: .exa),
                    credential: "test-key",
                    options: WebSearchFilterOptions())
            }
        } else {
            let results = try await client.search(
                query: "Swift",
                configuration: WebSearchConfiguration(provider: .exa),
                credential: "test-key",
                options: WebSearchFilterOptions()
            )
            #expect(results.isEmpty)
        }
    }

    @Test("Exa redacts transport failures and preserves cancellation")
    func transportFailures() async {
        await #expect(throws: WebSearchProviderError.unavailable) {
            try await ExaSearchClient(transport: SearchFailingTransport(error: .unavailable)).search(
                query: "Swift",
                configuration: WebSearchConfiguration(provider: .exa),
                credential: "test-key",
                options: WebSearchFilterOptions()
            )
        }
        await #expect(throws: CancellationError.self) {
            try await ExaSearchClient(transport: SearchFailingTransport(error: .cancelled)).search(
                query: "Swift",
                configuration: WebSearchConfiguration(provider: .exa),
                credential: "test-key",
                options: WebSearchFilterOptions()
            )
        }
    }
}
