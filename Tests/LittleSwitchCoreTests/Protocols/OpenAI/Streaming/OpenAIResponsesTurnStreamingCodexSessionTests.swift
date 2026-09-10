import Foundation
import Testing

@testable import LittleSwitchCore

extension OpenAIResponsesTurnStreamingTests {
    @Test("Codex sees one exact native web-search item across the search barrier")
    func codexSearchFixture() throws {
        let prepared = try preparedWebSearchRequest()
        var session = ResponsesPublicStreamSession(webSearch: prepared)
        var frames = try startCodexSearchSession(&session)

        let searchStart = try session.beginSearch(id: "ws_public", query: "latest Swift")
        #expect(searchStart.count == 3)
        frames += searchStart

        var interleavingAttempt = session
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try interleavingAttempt.consumePublic(
                .outputItemAdded(
                    outputIndex: 1,
                    itemJSON: responseData([
                        "id": "msg_interleaved",
                        "type": "message",
                        "status": "in_progress",
                        "role": "assistant",
                        "content": [],
                    ])
                )
            )
        }

        let searchFinish = try session.finishSearch(id: "ws_public", query: "latest Swift")
        #expect(searchFinish.count == 2)
        frames += searchFinish
        try expectCodexSearchFixture(frames)
    }
}
