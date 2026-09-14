import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchSearch

@Suite("Tavily search client")
struct TavilySearchClientTests {
    @Test("Search sends the Tavily request with bearer authentication")
    func searchRequest() async throws {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: #"{"results":[]}"#)
        ])
        let client = TavilySearchClient(transport: transport)

        _ = try await client.search(
            query: "current Swift release",
            configuration: .tavily,
            credential: "tvly-secret",
            options: WebSearchFilterOptions(),
        )

        let request = try #require(await transport.requests.first)
        #expect(request.url == "https://api.tavily.com/search")
        #expect(request.method == .POST)
        #expect(request.headers["authorization"] == ["Bearer tvly-secret"])
        #expect(request.headers["content-type"] == ["application/json"])
        #expect(request.headers["accept"] == ["application/json"])
        let object = try #require(
            JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        #expect(object["query"] as? String == "current Swift release")
        #expect(object["max_results"] as? Int == 10)
        #expect(Set(object.keys) == ["query", "max_results"])
    }

    @Test("Domain filters are forwarded; unsupported location filters are dropped")
    func filters() async throws {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: #"{"results":[]}"#)
        ])

        _ = try await TavilySearchClient(transport: transport).search(
            query: "Swift events",
            configuration: .tavily,
            credential: "tvly-secret",
            options: WebSearchFilterOptions(
                includeDomains: ["swift.org", "github.com"],
                excludeDomains: ["example.com"],
                location: "Paris, Ile-de-France",
                country: "FR"
            )
        )

        let request = try #require(await transport.requests.first)
        let object = try #require(
            JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        #expect(object["include_domains"] as? [String] == ["swift.org", "github.com"])
        #expect(object["exclude_domains"] as? [String] == ["example.com"])
        #expect(object["location"] == nil)
        #expect(object["country"] == nil)
        #expect(
            Set(object.keys)
                == ["query", "max_results", "include_domains", "exclude_domains"]
        )
    }

    @Test("Successful responses normalize valid hits and skip malformed hits")
    func responseParsing() async throws {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(
                body: """
                    {
                      "query": "Swift",
                      "results": [
                        {
                          "title": "Swift.org",
                          "url": "https://swift.org/",
                          "content": "The Swift project website",
                          "score": 0.98
                        },
                        {
                          "title": "Documentation",
                          "url": "http://example.com/docs",
                          "content": "API reference"
                        },
                        {"title": "", "url": "https://invalid.example", "content": "x"},
                        {"title": "FTP", "url": "ftp://example.com", "content": "x"},
                        {"url": "https://missing-title.example", "content": "x"},
                        {"title": "Missing content", "url": "https://example.com/none"}
                      ],
                      "response_time": 0.42,
                      "request_id": "ignored"
                    }
                    """
            )
        ])
        let client = TavilySearchClient(transport: transport)

        let results = try await client.search(
            query: "Swift",
            configuration: .tavily,
            credential: "key",
            options: WebSearchFilterOptions(),
        )

        #expect(
            results == [
                WebSearchResult(
                    title: "Swift.org",
                    url: "https://swift.org/",
                    content: "The Swift project website"
                ),
                WebSearchResult(
                    title: "Documentation",
                    url: "http://example.com/docs",
                    content: "API reference"
                ),
                WebSearchResult(
                    title: "Missing content",
                    url: "https://example.com/none",
                    content: ""
                ),
            ]
        )
    }

    @Test("Tavily requires a credential before sending a request")
    func missingCredential() async {
        let transport = SearchRecordingTransport(responses: [])
        let client = TavilySearchClient(transport: transport)

        await #expect(throws: WebSearchProviderError.missingCredential) {
            try await client.search(
                query: "Swift",
                configuration: .tavily,
                credential: nil,
                options: WebSearchFilterOptions(),
            )
        }
        #expect(await transport.requests.isEmpty)

        await #expect(throws: WebSearchProviderError.missingCredential) {
            try await client.search(
                query: "Swift",
                configuration: .tavily,
                credential: " \n\t ",
                options: WebSearchFilterOptions(),
            )
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Disabled configuration is rejected before transport")
    func disabledConfiguration() async {
        let transport = SearchRecordingTransport(responses: [])
        let client = TavilySearchClient(transport: transport)

        await #expect(throws: WebSearchProviderError.invalidResponse) {
            try await client.search(
                query: "Swift",
                configuration: .disabled,
                credential: nil,
                options: WebSearchFilterOptions(),
            )
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test(
        "Authentication, quota, and generic statuses map to redacted errors",
        arguments: [
            (HTTPResponseStatus.unauthorized, WebSearchProviderError.unauthorized),
            (HTTPResponseStatus.forbidden, WebSearchProviderError.unauthorized),
            (HTTPResponseStatus.tooManyRequests, WebSearchProviderError.rateLimited),
            (HTTPResponseStatus(statusCode: 432), WebSearchProviderError.rateLimited),
            (HTTPResponseStatus(statusCode: 433), WebSearchProviderError.rateLimited),
            (HTTPResponseStatus.internalServerError, WebSearchProviderError.httpStatus(500)),
        ]
    )
    func statusErrors(
        status: HTTPResponseStatus,
        expected: WebSearchProviderError
    ) async {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(status: status, body: #"{"private":"body"}"#)
        ])
        let client = TavilySearchClient(transport: transport)

        await #expect(throws: expected) {
            try await client.search(
                query: "Swift",
                configuration: .tavily,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }
    }

    @Test(
        "Invalid semantic and JSON responses are rejected",
        arguments: [
            #"{"query":"Swift"}"#,
            #"{"results":null}"#,
            "{",
        ]
    )
    func invalidResponses(body: String) async {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: body)
        ])
        let client = TavilySearchClient(transport: transport)

        await #expect(throws: WebSearchProviderError.invalidResponse) {
            try await client.search(
                query: "Swift",
                configuration: .tavily,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }
    }

    @Test("Oversized responses fail with a bounded error")
    func oversizedResponse() async {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: String(repeating: "x", count: 32))
        ])
        let client = TavilySearchClient(
            transport: transport,
            maximumResponseBytes: 16
        )

        await #expect(throws: WebSearchProviderError.responseTooLarge) {
            try await client.search(
                query: "Swift",
                configuration: .tavily,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }
    }

    @Test("A response body at the exact configured limit is accepted")
    func exactResponseLimit() async throws {
        let body = #"{"results":[]}"#
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: body)
        ])
        let client = TavilySearchClient(
            transport: transport,
            maximumResponseBytes: body.utf8.count
        )

        let results = try await client.search(
            query: "Swift",
            configuration: .tavily,
            credential: "key",
            options: WebSearchFilterOptions(),
        )

        #expect(results.isEmpty)
    }

    @Test("Transport failures are redacted but cancellation is preserved")
    func transportErrors() async {
        let unavailable = SearchFailingTransport(error: .unavailable)
        await #expect(throws: WebSearchProviderError.unavailable) {
            try await TavilySearchClient(transport: unavailable).search(
                query: "Swift",
                configuration: .tavily,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }

        let cancelled = SearchFailingTransport(error: .cancelled)
        await #expect(throws: CancellationError.self) {
            try await TavilySearchClient(transport: cancelled).search(
                query: "Swift",
                configuration: .tavily,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }
    }

    @Test("Response stream cancellation and failures preserve safe error semantics")
    func responseStreamErrors() async {
        let cancelled = SearchRecordingTransport(responses: [
            searchFailingResponse(error: CancellationError())
        ])
        await #expect(throws: CancellationError.self) {
            try await TavilySearchClient(transport: cancelled).search(
                query: "Swift",
                configuration: .tavily,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }

        let unavailable = SearchRecordingTransport(responses: [
            searchFailingResponse(error: SearchResponseStreamError())
        ])
        await #expect(throws: WebSearchProviderError.unavailable) {
            try await TavilySearchClient(transport: unavailable).search(
                query: "Swift",
                configuration: .tavily,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }
    }
}

@Suite("Tavily search client policy")
struct TavilySearchClientPolicyTests {

    @Test("A limit past the Tavily ceiling is rejected before any request")
    func overCeilingLimitRejected() async throws {
        let transport = SearchRecordingTransport(responses: [])

        await #expect(throws: WebSearchConfiguration.Error.invalidResultsLimit) {
            _ = try await TavilySearchClient(transport: transport).search(
                query: "Swift",
                configuration: WebSearchConfiguration(provider: .tavily, resultsLimit: 21),
                credential: "key",
                options: WebSearchFilterOptions()
            )
        }
        #expect(await transport.requests.isEmpty)
    }
}
