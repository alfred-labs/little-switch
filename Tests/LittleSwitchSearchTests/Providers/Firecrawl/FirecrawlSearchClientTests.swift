import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchSearch

@Suite("Firecrawl search client")
struct FirecrawlSearchClientTests {
    @Test("Cloud search sends the Firecrawl v2 request with bearer authentication")
    func cloudRequest() async throws {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: #"{"success":true,"data":{"web":[]}}"#)
        ])
        let client = FirecrawlSearchClient(transport: transport)

        _ = try await client.search(
            query: "current Swift release",
            configuration: .firecrawlCloud,
            credential: "fc-secret",
            options: WebSearchFilterOptions(),
        )

        let request = try #require(await transport.requests.first)
        #expect(request.url == "https://api.firecrawl.dev/v2/search")
        #expect(request.method == .POST)
        #expect(request.headers["authorization"] == ["Bearer fc-secret"])
        #expect(request.headers["content-type"] == ["application/json"])
        let object = try #require(
            JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        #expect(object["query"] as? String == "current Swift release")
        #expect(object["limit"] as? Int == 10)
        let sources = try #require(object["sources"] as? [[String: String]])
        #expect(sources == [["type": "web"]])
        #expect(Set(object.keys) == ["query", "limit", "sources"])
    }

    @Test("Successful responses normalize valid web hits and skip malformed hits")
    func responseParsing() async throws {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(
                body: """
                    {
                      "success": true,
                      "data": {
                        "web": [
                          {
                            "title": "Swift.org",
                            "url": "https://swift.org/",
                            "description": "The Swift project website"
                          },
                          {
                            "title": "Documentation",
                            "url": "http://example.com/docs",
                            "markdown": "API reference"
                          },
                          {
                            "title": "Empty snippet",
                            "url": "https://example.com/empty"
                          },
                          {
                            "title": "Escaped path",
                            "url": "https://example.com/a%20b",
                            "description": "Valid escape"
                          },
                          {
                            "title": "IPv6 host",
                            "url": "http://[2001:db8::1]/docs",
                            "description": "IPv6"
                          },
                          {"title": "", "url": "https://invalid.example"},
                          {"title": "FTP", "url": "ftp://example.com"},
                          {"title": "Malformed escape", "url": "https://example.com/%ZZ"},
                          {"title": "Incomplete escape", "url": "https://example.com/%2"},
                          {"title": "User info", "url": "https://user:password@example.com/private"},
                          {"title": "File", "url": "file:///tmp/private"},
                          {"title": "Relative", "url": "/docs"},
                          {"title": "Missing host", "url": "https:///docs"},
                          {"title": "Missing URL"}
                        ]
                      }
                    }
                    """
            )
        ])
        let client = FirecrawlSearchClient(transport: transport)

        let results = try await client.search(
            query: "Swift",
            configuration: .firecrawlCloud,
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
                    title: "Empty snippet",
                    url: "https://example.com/empty",
                    content: ""
                ),
                WebSearchResult(
                    title: "Escaped path",
                    url: "https://example.com/a%20b",
                    content: "Valid escape"
                ),
                WebSearchResult(
                    title: "IPv6 host",
                    url: "http://[2001:db8::1]/docs",
                    content: "IPv6"
                ),
            ]
        )
    }

    @Test("Cloud requires a credential before sending a request")
    func missingCredential() async {
        let transport = SearchRecordingTransport(responses: [])
        let client = FirecrawlSearchClient(transport: transport)

        await #expect(throws: WebSearchProviderError.missingCredential) {
            try await client.search(
                query: "Swift",
                configuration: .firecrawlCloud,
                credential: nil,
                options: WebSearchFilterOptions(),
            )
        }
        #expect(await transport.requests.isEmpty)

        await #expect(throws: WebSearchProviderError.missingCredential) {
            try await client.search(
                query: "Swift",
                configuration: .firecrawlCloud,
                credential: " \n\t ",
                options: WebSearchFilterOptions(),
            )
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Disabled configuration is rejected before transport")
    func disabledConfiguration() async {
        let transport = SearchRecordingTransport(responses: [])
        let client = FirecrawlSearchClient(transport: transport)

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
        "HTTP authentication, rate-limit, and generic statuses map to redacted errors",
        arguments: [
            (HTTPResponseStatus.unauthorized, WebSearchProviderError.unauthorized),
            (HTTPResponseStatus.forbidden, WebSearchProviderError.unauthorized),
            (HTTPResponseStatus.tooManyRequests, WebSearchProviderError.rateLimited),
            (HTTPResponseStatus.internalServerError, WebSearchProviderError.httpStatus(500)),
        ]
    )
    func statusErrors(status: HTTPResponseStatus, expected: WebSearchProviderError) async {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(status: status, body: #"{"private":"body"}"#)
        ])
        let client = FirecrawlSearchClient(transport: transport)

        await #expect(throws: expected) {
            try await client.search(
                query: "Swift",
                configuration: .firecrawlCloud,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }
    }

    @Test(
        "Invalid semantic and JSON responses are rejected",
        arguments: [
            #"{"success":false,"data":{"web":[]}}"#,
            #"{"success":true,"data":{}}"#,
            "{",
        ]
    )
    func invalidResponses(body: String) async {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: body)
        ])
        let client = FirecrawlSearchClient(transport: transport)

        await #expect(throws: WebSearchProviderError.invalidResponse) {
            try await client.search(
                query: "Swift",
                configuration: .firecrawlCloud,
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
        let client = FirecrawlSearchClient(
            transport: transport,
            maximumResponseBytes: 16
        )

        await #expect(throws: WebSearchProviderError.responseTooLarge) {
            try await client.search(
                query: "Swift",
                configuration: .firecrawlCloud,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }
    }

    @Test("A response body at the exact configured limit is accepted")
    func exactResponseLimit() async throws {
        let body = #"{"success":true,"data":{"web":[]}}"#
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: body)
        ])
        let client = FirecrawlSearchClient(
            transport: transport,
            maximumResponseBytes: body.utf8.count
        )

        let results = try await client.search(
            query: "Swift",
            configuration: .firecrawlCloud,
            credential: "key",
            options: WebSearchFilterOptions(),
        )

        #expect(results.isEmpty)
    }

    @Test("Transport failures are redacted but cancellation is preserved")
    func transportErrors() async {
        let unavailable = SearchFailingTransport(error: .unavailable)
        await #expect(throws: WebSearchProviderError.unavailable) {
            try await FirecrawlSearchClient(transport: unavailable).search(
                query: "Swift",
                configuration: .firecrawlCloud,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }

        let cancelled = SearchFailingTransport(error: .cancelled)
        await #expect(throws: CancellationError.self) {
            try await FirecrawlSearchClient(transport: cancelled).search(
                query: "Swift",
                configuration: .firecrawlCloud,
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
            try await FirecrawlSearchClient(transport: cancelled).search(
                query: "Swift",
                configuration: .firecrawlCloud,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }

        let unavailable = SearchRecordingTransport(responses: [
            searchFailingResponse(error: SearchResponseStreamError())
        ])
        await #expect(throws: WebSearchProviderError.unavailable) {
            try await FirecrawlSearchClient(transport: unavailable).search(
                query: "Swift",
                configuration: .firecrawlCloud,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }
    }
}

@Suite("Firecrawl search options")
struct WebSearchFilterOptionsTests {
    @Test("Anthropic search options map to Firecrawl request fields")
    func searchOptions() async throws {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: #"{"success":true,"data":{"web":[]}}"#)
        ])
        let client = FirecrawlSearchClient(transport: transport)

        _ = try await client.search(
            query: "Swift events",
            configuration: .firecrawlCloud,
            credential: "fc-secret",
            options: WebSearchFilterOptions(
                includeDomains: ["swift.org", "github.com"],
                location: "Paris, Ile-de-France",
                country: "FR"
            )
        )

        let request = try #require(await transport.requests.first)
        let object = try #require(
            JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        #expect(object["includeDomains"] as? [String] == ["swift.org", "github.com"])
        #expect(object["excludeDomains"] == nil)
        #expect(object["location"] as? String == "Paris, Ile-de-France")
        #expect(object["country"] as? String == "FR")
    }

    @Test("Blocked domains map separately from allowed domains")
    func blockedDomains() async throws {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: #"{"success":true,"data":{"web":[]}}"#)
        ])

        _ = try await FirecrawlSearchClient(transport: transport).search(
            query: "Swift",
            configuration: .firecrawlCloud,
            credential: "key",
            options: WebSearchFilterOptions(excludeDomains: ["example.com"])
        )

        let request = try #require(await transport.requests.first)
        let object = try #require(
            JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        #expect(object["includeDomains"] == nil)
        #expect(object["excludeDomains"] as? [String] == ["example.com"])
    }
}
