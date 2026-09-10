import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI native web-search outcomes")
struct OpenAIResponsesWebSearchOutcomeTests {
    @Test("Public search actions retain only official URL source fields")
    func sanitizedSources() throws {
        let source: [String: Any] = [
            "type": "web_search_call", "id": "ws", "status": "completed",
            "action": [
                "type": "search", "query": "Swift", "queries": ["Swift", "Swift 6"],
                "sources": [
                    [
                        "type": "url", "url": "https://swift.org/", "title": "Swift",
                        "snippet": "Private provider field",
                    ],
                    ["type": "url", "url": "https://example.com/?lang=fr"],
                ],
            ],
        ]
        let expected: [String: Any] = [
            "type": "web_search_call", "id": "ws", "status": "completed",
            "action": [
                "type": "search", "query": "Swift", "queries": ["Swift", "Swift 6"],
                "sources": [
                    ["type": "url", "url": "https://swift.org/"],
                    ["type": "url", "url": "https://example.com/?lang=fr"],
                ],
            ],
        ]
        #expect(NSDictionary(dictionary: try OpenAIResponsesPublicSanitizer.item(source)).isEqual(to: expected))
    }

    @Test("Malformed or excessive source lists fail explicitly")
    func malformedSources() throws {
        let malformed: [Any] = [
            "invalid", NSNull(), [1], [[:]], [["type": "file", "url": "https://swift.org/"]],
            [["type": "url", "url": ""]], [["type": "url", "url": "file:///result"]],
            [["type": "url", "url": "https://user:password@example.com/"]], [["type": "url", "url": 1]],
            [["type": "url", "url": "https://example.com/" + String(repeating: "x", count: 8 * 1_024)]],
            Array(repeating: ["type": "url", "url": "https://swift.org/"], count: 101),
        ]
        for sources in malformed {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesPublicSanitizer.item([
                    "type": "web_search_call", "id": "ws", "status": "completed",
                    "action": ["type": "search", "query": "Swift", "sources": sources],
                ])
            }
        }
    }

    @Test("Completed searches preserve an explicitly empty source list")
    func emptySources() throws {
        let item: [String: Any] = [
            "type": "web_search_call", "id": "ws", "status": "completed",
            "action": ["type": "search", "query": "Swift", "sources": []],
        ]
        #expect(NSDictionary(dictionary: try OpenAIResponsesPublicSanitizer.item(item)).isEqual(to: item))
    }

    @Test("Buffered and live search outcomes agree on source URLs and failure status", arguments: [false, true])
    func publicOutcomeParity(failed: Bool) throws {
        let sources = ["https://swift.org/", "https://example.com/?lang=fr"]
        let expected = expectedSearchOutcome(sources: sources, failed: failed)
        let prepared = try preparedWebSearchRequest()
        let finalObject = responseObject(
            id: "resp_final",
            createdAt: 60,
            status: "completed",
            output: [],
            usage: .init(inputTokens: 1, outputTokens: 1)
        )
        let finalTurn = try OpenAIResponsesWebSearch.parseModelTurn(responseData(finalObject))
        var trace = ResponsesWebSearchTrace(
            id: "ws",
            callID: "call",
            query: "latest Swift",
            outputJSON: try responseData([
                functionCallItem(id: "fc", callID: "call", name: "web_search", arguments: "{}", status: "completed")
            ])
        )
        trace.sources = sources
        trace.failed = failed
        let buffered = try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: prepared, traces: [trace], finalTurn: finalTurn, usage: finalTurn.usage
        )
        let output = try #require((liveJSONObject(buffered)["output"] as? [[String: Any]])?.first)
        #expect(NSDictionary(dictionary: output).isEqual(to: expected))
        let sse = try OpenAIResponsesWebSearch.streamingResponse(
            prepared: prepared, traces: [trace], finalTurn: finalTurn, usage: finalTurn.usage
        )
        let bufferedEvents = try ResponsesStreamingTestSupport.events(sse)
        let bufferedDone = try #require(
            bufferedEvents.first { $0.name == "response.output_item.done" }?.payload["item"] as? [String: Any])
        #expect(NSDictionary(dictionary: bufferedDone).isEqual(to: expected))
        #expect(bufferedEvents.contains { $0.name == "response.web_search_call.completed" } == !failed)
        var session = ResponsesPublicStreamSession(webSearch: prepared)
        _ = try startCodexSearchSession(&session)
        _ = try session.beginSearch(id: "ws", query: "latest Swift")
        let frames = try session.finishSearch(id: "ws", query: "latest Swift", sources: sources, failed: failed)
        let liveEvents = try publicEvents(frames)
        let liveDone = try #require(liveEvents.last?.payload["item"] as? [String: Any])
        #expect(NSDictionary(dictionary: liveDone).isEqual(to: expected))
        #expect(
            liveEvents.map(\.name)
                == (failed
                    ? ["response.output_item.done"]
                    : ["response.web_search_call.completed", "response.output_item.done"]))
        let terminal = try session.finish(responseJSON: responseData(finalObject), usage: finalTurn.usage)
        let final = try #require(publicEvents(terminal).last?.payload["response"] as? [String: Any])
        let finalOutput = try #require((final["output"] as? [[String: Any]])?.first)
        #expect(NSDictionary(dictionary: finalOutput).isEqual(to: expected))
    }

    @Test("A failed search does not emit a successful search-completed event")
    func failedSearchLifecycle() throws {
        let item = expectedSearchOutcome(sources: [], failed: true)
        let root = responseObject(
            id: "resp",
            createdAt: 60,
            status: "completed",
            output: [item],
            usage: .init(inputTokens: 1, outputTokens: 1)
        )
        let events = try ResponsesStreamingTestSupport.events(OpenAIResponsesStreaming.encode(completed: root))
        #expect(!events.contains { $0.name == "response.web_search_call.completed" })
        #expect(!events.contains { $0.name == "response.web_search_call.failed" })
        let done = try #require(
            events.first { $0.name == "response.output_item.done" }?.payload["item"] as? [String: Any])
        #expect(NSDictionary(dictionary: done).isEqual(to: item))
    }
}

private func expectedSearchOutcome(sources: [String], failed: Bool) -> [String: Any] {
    var action: [String: Any] = ["type": "search", "query": "latest Swift"]
    if !sources.isEmpty {
        action["sources"] = sources.map { ["type": "url", "url": $0] }
    }
    return ["id": "ws", "type": "web_search_call", "status": failed ? "failed" : "completed", "action": action]
}
