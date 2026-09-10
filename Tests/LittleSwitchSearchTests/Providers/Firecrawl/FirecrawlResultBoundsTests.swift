import AsyncHTTPClient
import Foundation
import NIOCore
import Testing

@testable import LittleSwitchSearch

@Suite("Firecrawl retained result bounds")
struct FirecrawlRetainedResultBoundsTests {
    @Test("Content budget is shared by results in response order")
    func aggregateContentBudget() async throws {
        let results = try await search(
            web: [
                hit(title: "One", path: "one", content: "abcd"),
                hit(title: "Two", path: "two", content: "efghij"),
                hit(title: "Three", path: "three", content: "klm"),
            ],
            maximumContentBytes: 7
        )

        #expect(results.map(\.content) == ["abcd", "efg", ""])
        #expect(results.reduce(0) { $0 + $1.content.utf8.count } == 7)
    }

    @Test("Unicode content is truncated at a valid UTF-8 boundary")
    func unicodeBoundary() async throws {
        let results = try await search(
            web: [
                hit(title: "Emoji", path: "emoji", content: "🙂🙂🙂🙂🙂"),
                hit(title: "Later", path: "later", content: "unused"),
            ],
            maximumContentBytes: 16
        )

        #expect(results.map(\.content) == ["🙂 [truncated]", ""])
        #expect(results[0].content.utf8.count == 16)
    }

    @Test("Zero content budget preserves result metadata")
    func zeroContentBudget() async throws {
        let results = try await search(
            web: [hit(title: "Title", path: "zero", content: "content")],
            maximumContentBytes: 0
        )

        #expect(
            results == [
                WebSearchResult(
                    title: "Title",
                    url: "https://example.com/zero",
                    content: ""
                )
            ]
        )
    }

    @Test("A budget smaller than the marker retains only fitting content")
    func smallContentBudget() async throws {
        let results = try await search(
            web: [
                hit(title: "One", path: "one", content: "abcdef"),
                hit(title: "Two", path: "two", content: "later"),
            ],
            maximumContentBytes: 3
        )

        #expect(results.map(\.content) == ["abc", ""])
    }

    @Test("Ordinary content remains byte-for-byte unchanged")
    func ordinaryContentIsExact() async throws {
        let content = "\n exact 🙂 content \n"
        let results = try await search(
            web: [hit(title: "Exact", path: "exact", content: content)],
            maximumContentBytes: content.utf8.count
        )

        #expect(
            results == [
                WebSearchResult(
                    title: "Exact",
                    url: "https://example.com/exact",
                    content: content
                )
            ]
        )
    }

    @Test("The default aggregate content budget is 256 KiB")
    func defaultContentBudget() async throws {
        let content = String(repeating: "x", count: 256 * 1_024 + 1)
        let transport = SearchRecordingTransport(responses: [
            try firecrawlResponse(web: [hit(title: "Large", path: "large", content: content)])
        ])

        let results = try await FirecrawlSearchClient(transport: transport).search(
            query: "Swift",
            configuration: .firecrawlCloud,
            credential: "key",
            options: WebSearchFilterOptions(),
        )

        let retained = try #require(results.first?.content)
        #expect(retained.utf8.count == 256 * 1_024)
        #expect(retained.hasSuffix(" [truncated]"))
    }

    @Test("Malformed hits do not let the server exceed the configured result count")
    func resultCount() async throws {
        let transport = SearchRecordingTransport(responses: [
            try firecrawlResponse(web: [
                ["title": "", "url": "https://example.com/invalid"],
                hit(title: "One", path: "one", content: "1"),
                hit(title: "Two", path: "two", content: "2"),
                hit(title: "Three", path: "three", content: "3"),
            ])
        ])
        let configuration = WebSearchConfiguration(resultsLimit: 2)

        let results = try await FirecrawlSearchClient(transport: transport).search(
            query: "Swift",
            configuration: configuration,
            credential: "key",
            options: WebSearchFilterOptions(),
        )

        #expect(results.map(\.title) == ["One", "Two"])
    }

    @Test("Oversized titles and URLs are rejected at inclusive byte limits")
    func metadataBounds() async throws {
        let exactTitle = String(repeating: "t", count: 4 * 1_024)
        let exactURLPrefix = "https://example.com/"
        let exactURL =
            exactURLPrefix
            + String(repeating: "u", count: 8 * 1_024 - exactURLPrefix.utf8.count)
        let transport = SearchRecordingTransport(responses: [
            try firecrawlResponse(web: [
                hit(
                    title: String(repeating: "🙂", count: 1_025),
                    url: "https://example.com/oversized-title",
                    content: "rejected"
                ),
                hit(title: "Oversized URL", url: exactURL + "u", content: "rejected"),
                hit(title: exactTitle, url: exactURL, content: "accepted"),
            ])
        ])

        let results = try await FirecrawlSearchClient(transport: transport).search(
            query: "Swift",
            configuration: .firecrawlCloud,
            credential: "key",
            options: WebSearchFilterOptions(),
        )

        #expect(
            results == [
                WebSearchResult(title: exactTitle, url: exactURL, content: "accepted")
            ]
        )
    }

    private func search(
        web: [[String: String]],
        maximumContentBytes: Int
    ) async throws -> [WebSearchResult] {
        let transport = SearchRecordingTransport(responses: [
            try firecrawlResponse(web: web)
        ])
        return try await FirecrawlSearchClient(
            transport: transport,
            maximumContentBytes: maximumContentBytes
        ).search(
            query: "Swift",
            configuration: .firecrawlCloud,
            credential: "key",
            options: WebSearchFilterOptions(),
        )
    }

    private func hit(
        title: String,
        path: String,
        content: String
    ) -> [String: String] {
        hit(title: title, url: "https://example.com/\(path)", content: content)
    }

    private func hit(
        title: String,
        url: String,
        content: String
    ) -> [String: String] {
        ["title": title, "url": url, "description": content]
    }
}

private func firecrawlResponse(web: [[String: String]]) throws -> HTTPClientResponse {
    let data = try JSONSerialization.data(
        withJSONObject: ["success": true, "data": ["web": web]]
    )
    // JSONSerialization output is always valid UTF-8.
    // swiftlint:disable:next optional_data_string_conversion
    let body = String(decoding: data, as: UTF8.self)
    return searchResponse(body: body)
}
