import Foundation
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Portable web-search history")
struct PortableWebSearchHistoryTests {
    @Test("Published Anthropic search tokens retain complete normalized results")
    func publishedResultRoundTrip() throws {
        let expected = [
            WebSearchResult(
                title: "Swift — évolution",
                url: "https://swift.org/?query=concurrency&lang=fr",
                content: "First line.\nSecond line: actors, async/await and 🐦."
            ),
            WebSearchResult(title: "Empty excerpt", url: "https://example.com/", content: ""),
        ]
        let content = try AnthropicWebSearch.responseContent(
            traces: [
                WebSearchTrace(toolUseID: "srvtoolu_roundtrip", query: "Swift", content: .results(expected))
            ],
            finalTurn: bareAnthropicTurn(contentJSON: Data("[]".utf8))
        )
        let block = try #require(content.last)
        let results = try #require(block["content"]?.anthropicObjects)
        let recovered = try results.enumerated().map { index, result in
            let token = try #require(result["encrypted_content"]?.string)
            let prefix = "little-switch-search:v1:"
            try #require(token.hasPrefix(prefix))
            let data = try #require(Data(base64Encoded: String(token.dropFirst(prefix.count))))
            let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(payload["tool_use_id"] as? String == "srvtoolu_roundtrip")
            #expect(payload["result_index"] as? Int == index)
            let serialized = try JSONSerialization.data(withJSONObject: #require(payload["result"]))
            return try JSONDecoder().decode(WebSearchResult.self, from: serialized)
        }
        #expect(recovered == expected)
    }

    @Test("Published search results replay as complete readable history")
    func readablePublishedResults() throws {
        let expected =
            "Historical web search result for srvtoolu_replay:\n"
            + "Title: Swift.org\nURL: https://swift.org/\nContent: First line.\nSecond line: 🐦.\n\n"
            + "Title: Empty excerpt\nURL: https://example.com/\nContent: \n\n"
        let block = try publishedSearchResult(
            .results([
                WebSearchResult(title: "Swift.org", url: "https://swift.org/", content: "First line.\nSecond line: 🐦."),
                WebSearchResult(title: "Empty excerpt", url: "https://example.com/", content: ""),
            ])
        )
        #expect(try anthropicReplayText(block) == expected)
    }

    @Test("Empty search results retain an explicit completed result")
    func emptyResults() throws {
        let block = try publishedSearchResult(.results([]))
        #expect(
            try anthropicReplayText(block)
                == "Historical web search result for srvtoolu_replay:\nNo results were returned."
        )
    }

    @Test("Search error history retains the native error code")
    func errorResult() throws {
        let block = try publishedSearchResult(.error("invalid_request"))
        #expect(
            try anthropicReplayText(block)
                == "Historical web search result for srvtoolu_replay:\nWeb search failed: invalid_tool_input."
        )
    }

    @Test("Legacy gateway tokens retain source metadata and explain missing content")
    func legacyResult() throws {
        let block = replayedSearchBlock(token: "little-switch-opaque:srvtoolu_replay:0")
        #expect(
            try anthropicReplayText(block)
                == "Historical web search result for srvtoolu_replay:\n"
                + "Title: Swift.org\nURL: https://swift.org/\n"
                + "Content: Content unavailable: this legacy LittleSwitch replay token retained only source metadata.\n\n"
        )
    }

    @Test("Foreign opaque search tokens cannot masquerade as portable history")
    func foreignOpaqueResult() throws {
        #expect(throws: PortableWebSearchHistory.Error.unsupportedOpaqueContent) {
            try anthropicReplayText(replayedSearchBlock(token: "native-opaque-provider-data"))
        }
    }

    @Test("Unknown gateway replay versions fail explicitly")
    func unsupportedVersion() throws {
        #expect(throws: PortableWebSearchHistory.Error.unsupportedReplayVersion) {
            try anthropicReplayText(replayedSearchBlock(token: "little-switch-search:v2:e30="))
        }
    }

    @Test("Live SSE and buffered search results carry exactly the same replay values")
    func bufferedStreamingParity() throws {
        let contents: [WebSearchTraceContent] = [
            .results([WebSearchResult(title: "Swift.org", url: "https://swift.org/", content: "Readable 🐦 excerpt.")]),
            .results([]),
            .error("invalid_request"),
        ]
        for content in contents {
            var session = AnthropicPublicStreamSession(originalModel: "claude")
            _ = try session.start(from: messageStartEvent(id: "msg", inputTokens: 1))
            _ = try feedPrivateSearchTurn(into: &session, providerToolID: "toolu_private", query: "Swift")
            _ = try session.beginSearch(toolUseID: "srvtoolu_replay", query: "Swift")
            let frames = try session.finishSearch(
                WebSearchTrace(toolUseID: "srvtoolu_replay", query: "Swift", content: content)
            )
            let events = try parsePublicFrames(frames)
            let streamed = try #require(events.first?.payload["content_block"] as? [String: Any])
            let buffered = try publishedSearchResult(content)
            #expect(NSDictionary(dictionary: streamed).isEqual(to: buffered))
            #expect(
                try anthropicReplayText(streamed)
                    == anthropicReplayText(buffered)
            )
        }
    }
}

func publishedSearchResult(_ content: WebSearchTraceContent) throws -> [String: Any] {
    let blocks = try AnthropicWebSearch.responseContent(
        traces: [WebSearchTrace(toolUseID: "srvtoolu_replay", query: "Swift", content: content)],
        finalTurn: bareAnthropicTurn(contentJSON: Data("[]".utf8))
    )
    return try anthropicFoundationObject(#require(blocks.last))
}

func replayedSearchBlock(token: String) -> [String: Any] {
    [
        "type": "web_search_tool_result",
        "tool_use_id": "srvtoolu_replay",
        "content": [
            [
                "type": "web_search_result",
                "title": "Swift.org",
                "url": "https://swift.org/",
                "encrypted_content": token,
                "page_age": NSNull(),
            ]
        ],
    ]
}
