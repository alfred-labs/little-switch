import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchSearch

@Suite("Brave search client")
struct BraveSearchClientTests {
    @Test("Search sends the Brave request with the subscription token")
    func searchRequest() async throws {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: #"{"type":"search","web":{"results":[]}}"#)
        ])
        let client = BraveSearchClient(transport: transport)

        _ = try await client.search(
            query: "current Swift release",
            configuration: .brave,
            credential: "brave-secret",
            options: WebSearchFilterOptions(),
        )

        let request = try #require(await transport.requests.first)
        let components = try #require(URLComponents(string: request.url))
        #expect(components.scheme == "https")
        #expect(components.host == "api.search.brave.com")
        #expect(components.path == "/res/v1/web/search")
        #expect(
            components.queryItems == [
                URLQueryItem(name: "q", value: "current Swift release"),
                URLQueryItem(name: "count", value: "10"),
            ])
        #expect(request.method == .GET)
        #expect(request.headers["x-subscription-token"] == ["brave-secret"])
        #expect(request.headers["authorization"].isEmpty)
        #expect(request.headers["accept"] == ["application/json"])
        #expect(request.headers["content-type"].isEmpty)
        #expect(request.body.isEmpty)
    }

    @Test("The country filter is forwarded; domain and location filters are dropped")
    func filters() async throws {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: #"{"type":"search","web":{"results":[]}}"#)
        ])

        _ = try await BraveSearchClient(transport: transport).search(
            query: "Swift events",
            configuration: .brave,
            credential: "brave-secret",
            options: WebSearchFilterOptions(
                includeDomains: ["swift.org", "github.com"],
                excludeDomains: ["example.com"],
                location: "Paris, Ile-de-France",
                country: "fr"
            )
        )

        let request = try #require(await transport.requests.first)
        let components = try #require(URLComponents(string: request.url))
        #expect(
            components.queryItems == [
                URLQueryItem(name: "q", value: "Swift events"),
                URLQueryItem(name: "count", value: "10"),
                URLQueryItem(name: "country", value: "fr"),
            ])
    }

    @Test("Successful responses normalize valid hits and skip malformed hits")
    func responseParsing() async throws {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(
                body: """
                    {
                      "type": "search",
                      "query": {"original": "Swift"},
                      "web": {
                        "type": "list",
                        "results": [
                          {
                            "title": "Swift.org",
                            "url": "https://swift.org/",
                            "description": "The Swift project website"
                          },
                          {
                            "title": "Documentation",
                            "url": "http://example.com/docs",
                            "description": "API reference"
                          },
                          {"title": "", "url": "https://invalid.example", "description": "x"},
                          {"title": "FTP", "url": "ftp://example.com", "description": "x"},
                          {"url": "https://missing-title.example", "description": "x"},
                          {"title": "Missing description", "url": "https://example.com/none"}
                        ]
                      }
                    }
                    """
            )
        ])
        let client = BraveSearchClient(transport: transport)

        let results = try await client.search(
            query: "Swift",
            configuration: .brave,
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
                    title: "Missing description",
                    url: "https://example.com/none",
                    content: ""
                ),
            ]
        )
    }

    @Test(
        "A response without web results is a valid empty answer",
        arguments: [
            #"{"type":"search","query":{"original":"Swift"},"discussions":{}}"#,
            #"{"type":"search","web":null}"#,
            #"{"type":"search","web":{}}"#,
        ]
    )
    func missingWebSection(body: String) async throws {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: body)
        ])
        let client = BraveSearchClient(transport: transport)

        let results = try await client.search(
            query: "Swift",
            configuration: .brave,
            credential: "key",
            options: WebSearchFilterOptions(),
        )

        #expect(results.isEmpty)
    }

    @Test("Reserved query characters are percent-encoded, including a literal plus")
    func reservedEncoding() async throws {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: #"{"type":"search","web":{"results":[]}}"#)
        ])
        let client = BraveSearchClient(transport: transport)

        _ = try await client.search(
            query: "C++ coroutines 100% a&b=c\né",
            configuration: .brave,
            credential: "key",
            options: WebSearchFilterOptions(),
        )

        // A literal '+' must ride the URL as %2B: the API's form-style
        // query decoding would otherwise read it as a space. Control and
        // multi-byte characters encode per UTF-8 byte.
        let request = try #require(await transport.requests.first)
        #expect(
            request.url
                == "https://api.search.brave.com/res/v1/web/search"
                + "?q=C%2B%2B%20coroutines%20100%25%20a%26b%3Dc%0A%C3%A9&count=10"
        )
    }

    @Test("Brave requires a credential before sending a request")
    func missingCredential() async {
        let transport = SearchRecordingTransport(responses: [])
        let client = BraveSearchClient(transport: transport)

        await #expect(throws: WebSearchProviderError.missingCredential) {
            try await client.search(
                query: "Swift",
                configuration: .brave,
                credential: nil,
                options: WebSearchFilterOptions(),
            )
        }
        #expect(await transport.requests.isEmpty)

        await #expect(throws: WebSearchProviderError.missingCredential) {
            try await client.search(
                query: "Swift",
                configuration: .brave,
                credential: " \n\t ",
                options: WebSearchFilterOptions(),
            )
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Disabled configuration is rejected before transport")
    func disabledConfiguration() async {
        let transport = SearchRecordingTransport(responses: [])
        let client = BraveSearchClient(transport: transport)

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

}

/// The error-mapping half of the client contract: status decoding, envelope
/// rejection, and the transport failure ladder live beside the request-shape
/// suite without growing its body past review size.
@Suite("Brave search client error mapping")
struct BraveSearchClientErrorTests {
    @Test(
        "Authentication, quota, and generic statuses map to redacted errors",
        arguments: [
            (HTTPResponseStatus.unauthorized, WebSearchProviderError.unauthorized),
            (HTTPResponseStatus.forbidden, WebSearchProviderError.unauthorized),
            (HTTPResponseStatus.tooManyRequests, WebSearchProviderError.rateLimited),
            (HTTPResponseStatus(statusCode: 422), WebSearchProviderError.httpStatus(422)),
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
        let client = BraveSearchClient(transport: transport)

        await #expect(throws: expected) {
            try await client.search(
                query: "Swift",
                configuration: .brave,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }
    }

    @Test(
        "Undecodable or non-search JSON responses are rejected",
        arguments: [
            "{",
            "[]",
            #"{"web":null}"#,
            #"{"error":{"code":"some outage"}}"#,
        ]
    )
    func invalidResponses(body: String) async {
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: body)
        ])
        let client = BraveSearchClient(transport: transport)

        await #expect(throws: WebSearchProviderError.invalidResponse) {
            try await client.search(
                query: "Swift",
                configuration: .brave,
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
        let client = BraveSearchClient(
            transport: transport,
            maximumResponseBytes: 16
        )

        await #expect(throws: WebSearchProviderError.responseTooLarge) {
            try await client.search(
                query: "Swift",
                configuration: .brave,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }
    }

    @Test("A response body at the exact configured limit is accepted")
    func exactResponseLimit() async throws {
        let body = #"{"type":"search","web":{"results":[]}}"#
        let transport = SearchRecordingTransport(responses: [
            searchResponse(body: body)
        ])
        let client = BraveSearchClient(
            transport: transport,
            maximumResponseBytes: body.utf8.count
        )

        let results = try await client.search(
            query: "Swift",
            configuration: .brave,
            credential: "key",
            options: WebSearchFilterOptions(),
        )

        #expect(results.isEmpty)
    }

    @Test("Transport failures are redacted but cancellation is preserved")
    func transportErrors() async {
        let unavailable = SearchFailingTransport(error: .unavailable)
        await #expect(throws: WebSearchProviderError.unavailable) {
            try await BraveSearchClient(transport: unavailable).search(
                query: "Swift",
                configuration: .brave,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }

        let cancelled = SearchFailingTransport(error: .cancelled)
        await #expect(throws: CancellationError.self) {
            try await BraveSearchClient(transport: cancelled).search(
                query: "Swift",
                configuration: .brave,
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
            try await BraveSearchClient(transport: cancelled).search(
                query: "Swift",
                configuration: .brave,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }

        let unavailable = SearchRecordingTransport(responses: [
            searchFailingResponse(error: SearchResponseStreamError())
        ])
        await #expect(throws: WebSearchProviderError.unavailable) {
            try await BraveSearchClient(transport: unavailable).search(
                query: "Swift",
                configuration: .brave,
                credential: "key",
                options: WebSearchFilterOptions(),
            )
        }
    }
}

@Suite("Brave search client policy")
struct BraveSearchClientPolicyTests {

    @Test("A limit past the Brave ceiling is rejected before any request")
    func overCeilingLimitRejected() async throws {
        let transport = SearchRecordingTransport(responses: [])

        await #expect(throws: WebSearchConfiguration.Error.invalidResultsLimit) {
            _ = try await BraveSearchClient(transport: transport).search(
                query: "Swift",
                configuration: WebSearchConfiguration(provider: .brave, resultsLimit: 21),
                credential: "key",
                options: WebSearchFilterOptions()
            )
        }
        #expect(await transport.requests.isEmpty)
    }
}
