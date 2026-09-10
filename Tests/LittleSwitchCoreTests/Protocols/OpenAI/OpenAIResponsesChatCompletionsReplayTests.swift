import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses Chat Completions replay")
struct OpenAIChatReplayTests {
    @Test("Codex web search history is validated and preserved in the next ZAI turn")
    func preservesReplayedWebSearchItems() throws {
        for status in ["in_progress", "completed"] {
            let body = try responseData([
                "model": "route",
                "input": [
                    [
                        "type": "web_search_call", "id": "ws_1", "status": status,
                        "action": ["type": "search", "query": "Swift concurrency"],
                    ],
                    [
                        "type": "message", "role": "assistant",
                        "content": [["type": "output_text", "text": "Prior answer"]],
                    ],
                    [
                        "type": "message", "role": "user",
                        "content": [["type": "input_text", "text": "Continue"]],
                    ],
                ],
            ])

            let prepared = try OpenAIResponsesChatCompletions.prepare(
                body: body,
                targetModel: "glm-5"
            )
            let request = try #require(
                JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any]
            )
            let messages = try #require(request["messages"] as? [[String: Any]])

            #expect(messages.count == 3)
            #expect(messages[0]["role"] as? String == "assistant")
            let history = try #require(messages[0]["content"] as? String)
            let serialized = history.split(separator: "\n", maxSplits: 1).last.map(String.init)
            let original = try JSONSerialization.jsonObject(with: Data(#require(serialized).utf8))
            #expect(
                original as? NSDictionary == [
                    "type": "web_search_call", "id": "ws_1", "status": status,
                    "action": ["type": "search", "query": "Swift concurrency"],
                ] as NSDictionary)
            #expect(messages[1]["role"] as? String == "assistant")
            #expect(messages[1]["content"] as? String == "Prior answer")
            #expect(messages[2]["role"] as? String == "user")
            #expect(messages[2]["content"] as? String == "Continue")
        }
    }

    @Test("Malformed replayed web search output remains fail-closed")
    func rejectsMalformedReplayedWebSearchItems() throws {
        let malformedItems: [[String: Any]] = [
            ["type": "web_search_call", "status": "completed"],
            ["type": "web_search_call", "id": "ws", "status": "private"],
            ["type": "web_search_call", "id": "ws", "action": ["type": "private"]],
        ]
        for item in malformedItems {
            let body = try responseData([
                "model": "route",
                "input": [
                    item,
                    ["type": "message", "role": "user", "content": "Continue"],
                ],
            ])
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                _ = try OpenAIResponsesChatCompletions.prepare(
                    body: body,
                    targetModel: "glm-5"
                )
            }
        }
    }
}
