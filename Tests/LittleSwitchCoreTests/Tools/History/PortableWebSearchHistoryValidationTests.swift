import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

extension PortableWebSearchHistoryTests {
    @Test("Malformed replay payloads fail without becoming readable content")
    func malformedTokens() throws {
        for suffix in ["", "!", "====", "W10=", "e30=", "bnVsbA==", "eyI=", "/w=="] {
            #expect(throws: PortableWebSearchHistory.Error.invalidResult) {
                try anthropicReplayText(
                    replayedSearchBlock(token: "little-switch-search:v1:" + suffix)
                )
            }
        }
    }

    @Test("Replay tokens are bound to their call, result position, title and URL")
    func bindingValidation() throws {
        let result = WebSearchResult(title: "Swift.org", url: "https://swift.org/", content: "Read me")
        var tokens = ["little-switch-opaque:other:0", "little-switch-opaque:srvtoolu_replay:1"]
        for (id, index) in [("other", 0), ("srvtoolu_replay", 1)] {
            tokens.append(
                try PortableWebSearchHistory.anthropicReplayToken(toolUseID: id, resultIndex: index, result: result)
            )
        }
        for changed in [
            WebSearchResult(title: "Different title", url: result.url, content: result.content),
            WebSearchResult(title: result.title, url: "https://example.com/", content: result.content),
        ] {
            tokens.append(
                try PortableWebSearchHistory.anthropicReplayToken(
                    toolUseID: "srvtoolu_replay", resultIndex: 0, result: changed
                )
            )
        }
        for token in tokens {
            #expect(throws: PortableWebSearchHistory.Error.invalidResult) {
                try anthropicReplayText(replayedSearchBlock(token: token))
            }
        }
    }

    @Test("Malformed result blocks and unnormalized metadata are rejected")
    func malformedResults() throws {
        let base = replayedSearchBlock(token: "little-switch-opaque:srvtoolu_replay:0")
        let mutations: [(String, Any)] = [
            ("type", "tool_result"), ("tool_use_id", ""), ("tool_use_id", 1),
            ("content", "opaque"), ("content", NSNull()), ("content", [1]),
        ]
        for (key, value) in mutations {
            var block = base
            block[key] = value
            #expect(throws: PortableWebSearchHistory.Error.invalidResult) {
                try anthropicReplayText(block)
            }
        }
        let result = try #require((base["content"] as? [[String: Any]])?.first)
        let resultMutations: [(String, Any)] = [
            ("type", "text"), ("title", ""), ("title", " Swift.org "), ("title", 1),
            ("title", String(repeating: "x", count: 4 * 1_024 + 1)),
            ("url", "file:///private/result"), ("url", "https://user:secret@example.com/"),
            ("url", "https://example.com/" + String(repeating: "x", count: 8 * 1_024)),
            ("encrypted_content", 1), ("encrypted_content", ""),
        ]
        for (key, value) in resultMutations {
            var changed = result
            changed[key] = value
            var block = base
            block["content"] = [changed]
            #expect(throws: PortableWebSearchHistory.Error.invalidResult) {
                try anthropicReplayText(block)
            }
        }
    }

    @Test("Malformed search error values do not become successful historical output")
    func malformedErrors() throws {
        for content in [
            ["type": "error", "error_code": "unavailable"],
            ["type": "web_search_tool_result_error", "error_code": ""],
            ["type": "web_search_tool_result_error", "error_code": 1],
            ["type": "web_search_tool_result_error", "error_code": String(repeating: "x", count: 129)],
        ] as [[String: Any]] {
            var block = replayedSearchBlock(token: "unused")
            block["content"] = content
            #expect(throws: PortableWebSearchHistory.Error.invalidResult) {
                try anthropicReplayText(block)
            }
        }
    }

    @Test("Oversized encoded and decoded tokens are rejected before recovery")
    func oversizedTokens() throws {
        let oversizedEncoding = "little-switch-search:v1:" + String(repeating: "A", count: 3 * 1_024 * 1_024)
        var oversizedPayload = Data("{}".utf8)
        oversizedPayload.append(Data(repeating: 0x20, count: 2 * 1_024 * 1_024 - 1))
        let oversizedDecoding = "little-switch-search:v1:" + oversizedPayload.base64EncodedString()
        for token in [oversizedEncoding, oversizedDecoding] {
            #expect(throws: PortableWebSearchHistory.Error.resultTooLarge) {
                try anthropicReplayText(replayedSearchBlock(token: token))
            }
        }
    }

    @Test("Publication enforces normalized metadata, identifiers and result positions")
    func publicationValidation() throws {
        let result = WebSearchResult(title: "Swift.org", url: "https://swift.org/", content: "Read me")
        for (id, index) in [("", 0), ("srvtoolu_replay", -1)] {
            #expect(throws: PortableWebSearchHistory.Error.invalidResult) {
                try PortableWebSearchHistory.anthropicReplayToken(toolUseID: id, resultIndex: index, result: result)
            }
        }
        for (id, index) in [(String(repeating: "x", count: 1_025), 0), ("srvtoolu_replay", 100)] {
            #expect(throws: PortableWebSearchHistory.Error.resultTooLarge) {
                try PortableWebSearchHistory.anthropicReplayToken(toolUseID: id, resultIndex: index, result: result)
            }
        }
        #expect(throws: PortableWebSearchHistory.Error.invalidResult) {
            try publishedSearchResult(.results([WebSearchResult(title: "", url: result.url, content: result.content)]))
        }
    }

    @Test("A result larger than the search content budget cannot be published or replayed")
    func oversizedContent() throws {
        let content = String(repeating: "x", count: 256 * 1_024 + 1)
        let result = WebSearchResult(title: "Swift.org", url: "https://swift.org/", content: content)
        #expect(throws: PortableWebSearchHistory.Error.resultTooLarge) {
            try publishedSearchResult(.results([result]))
        }
        let payload: [String: Any] = [
            "tool_use_id": "srvtoolu_replay", "result_index": 0,
            "result": ["title": result.title, "url": result.url, "content": content],
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let token = "little-switch-search:v1:" + payloadData.base64EncodedString()
        #expect(throws: PortableWebSearchHistory.Error.resultTooLarge) {
            try anthropicReplayText(replayedSearchBlock(token: token))
        }
    }

    @Test("Search history applies the content budget to the whole result list")
    func aggregateContentBudget() throws {
        let result = WebSearchResult(
            title: "Swift.org", url: "https://swift.org/", content: String(repeating: "x", count: 128 * 1_024 + 1)
        )
        #expect(throws: PortableWebSearchHistory.Error.resultTooLarge) {
            try publishedSearchResult(.results([result, result]))
        }
        var block = replayedSearchBlock(token: "unused")
        block["content"] = try (0..<2).map { index in
            let token = try PortableWebSearchHistory.anthropicReplayToken(
                toolUseID: "srvtoolu_replay", resultIndex: index, result: result
            )
            return try #require((replayedSearchBlock(token: token)["content"] as? [[String: Any]])?.first)
        }
        #expect(throws: PortableWebSearchHistory.Error.resultTooLarge) {
            try anthropicReplayText(block)
        }
    }

    @Test("Search publication and replay reject more results than any configured provider supports")
    func resultCountBudget() throws {
        let result = WebSearchResult(title: "Swift.org", url: "https://swift.org/", content: "")
        #expect(throws: PortableWebSearchHistory.Error.resultTooLarge) {
            try publishedSearchResult(.results(Array(repeating: result, count: 101)))
        }
        var block = replayedSearchBlock(token: "unused")
        block["content"] = try (0..<101).map { index in
            let token = "little-switch-opaque:srvtoolu_replay:\(index)"
            return try #require((replayedSearchBlock(token: token)["content"] as? [[String: Any]])?.first)
        }
        #expect(throws: PortableWebSearchHistory.Error.resultTooLarge) {
            try anthropicReplayText(block)
        }
    }

    @Test("Maximum normalized fields remain lossless even with worst-case JSON escaping")
    func maximumNormalizedResult() throws {
        let urlPrefix = "https://example.com/"
        let result = WebSearchResult(
            title: String(repeating: "x", count: 4 * 1_024),
            url: urlPrefix + String(repeating: "x", count: 8 * 1_024 - urlPrefix.utf8.count),
            content: String(repeating: "\u{0000}", count: 256 * 1_024)
        )
        let block = try publishedSearchResult(.results([result]))
        #expect(
            try anthropicReplayText(block)
                == "Historical web search result for srvtoolu_replay:\n"
                + "Title: \(result.title)\nURL: \(result.url)\nContent: \(result.content)\n\n"
        )
    }
}
