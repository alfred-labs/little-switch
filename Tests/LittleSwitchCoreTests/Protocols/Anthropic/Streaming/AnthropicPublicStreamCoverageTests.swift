import Testing

@testable import LittleSwitchCore

@Suite("Anthropic public stream defensive coverage")
struct AnthropicPublicStreamCoverageTests {
    @Test("A search result must match the pending public search")
    func unmatchedSearchResult() {
        var session = AnthropicPublicStreamSession(originalModel: "claude")
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try session.finishSearch(
                WebSearchTrace(
                    toolUseID: "srvtoolu_missing",
                    query: "Swift",
                    content: .results([])
                )
            )
        }
    }
}
