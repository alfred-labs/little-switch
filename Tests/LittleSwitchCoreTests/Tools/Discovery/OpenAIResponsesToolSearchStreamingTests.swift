import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI client tool search streaming")
struct OpenAIResponsesToolSearchStreamingTests {
    @Test("Live calls publish search items without leaking the private function protocol")
    func liveSearchCall() throws {
        let prepared = try prepared(streaming: true)
        let contract = try #require(prepared.toolSearchContract)
        let start = try data([
            "id": "resp_search", "object": "response", "created_at": 1,
            "status": "in_progress", "output": [],
        ])
        var session = ResponsesPublicStreamSession(chatCompletions: prepared)
        var frames = try session.start(responseJSON: start)
        let call: [String: Any] = [
            "id": "fc_search", "type": "function_call", "status": "completed",
            "call_id": "call_search", "name": contract.wireName,
            "arguments": "{\"goal\":\"read files\"}",
        ]
        var pending = call
        pending["arguments"] = ""
        pending["status"] = "in_progress"
        frames += try session.consumePublic(.outputItemAdded(outputIndex: 0, itemJSON: data(pending)))
        let delta = try session.consumePublic(
            .functionArgumentsDelta(
                outputIndex: 0, itemID: "fc_search", callID: "call_search", name: contract.wireName, delta: "{\"goal\":"
            ))
        let done = try session.consumePublic(
            .functionArgumentsDone(
                outputIndex: 0,
                itemID: "fc_search",
                callID: "call_search",
                name: contract.wireName,
                arguments: "{\"goal\":\"read files\"}"
            ))
        #expect(delta.isEmpty)
        #expect(done.isEmpty)
        frames += try session.consumePublic(.outputItemDone(outputIndex: 0, itemJSON: data(call)))
        let terminal = try data([
            "id": "resp_search", "object": "response", "created_at": 1,
            "status": "completed", "output": [call], "usage": [:],
        ])
        frames += try session.consumePublic(.terminal(status: .completed, responseJSON: terminal))
        frames += try session.finish(responseJSON: terminal, usage: ResponsesUsage(inputTokens: 1, outputTokens: 1))
        let text = try #require(String(data: frames.reduce(into: Data()) { $0.append($1) }, encoding: .utf8))
        #expect(!text.contains(contract.wireName))
        #expect(!text.contains("function_call_arguments"))
        #expect(text.contains("\"type\":\"tool_search_call\""))
        #expect(text.contains("\"arguments\":{\"goal\":\"read files\"}"))
        #expect(text.contains("response.completed"))
    }

    @Test("Buffered SSE encodes the restored client search contract")
    func bufferedSearchSSE() throws {
        let prepared = try prepared(streaming: true)
        let contract = try #require(prepared.toolSearchContract)
        let body = try OpenAIResponsesChatCompletions.project(
            responseBody: data([
                "id": "chat_search", "created": 1,
                "choices": [
                    [
                        "finish_reason": "tool_calls",
                        "message": [
                            "content": NSNull(),
                            "tool_calls": [
                                [
                                    "id": "call_1", "type": "function",
                                    "function": ["name": contract.wireName, "arguments": "{\"goal\":\"reader\"}"],
                                ]
                            ],
                        ],
                    ]
                ],
            ]),
            prepared: prepared
        )
        let text = try #require(String(data: body, encoding: .utf8))
        #expect(text.contains("response.output_item.added"))
        #expect(text.contains("response.output_item.done"))
        #expect(text.contains("\"type\":\"tool_search_call\""))
        #expect(!text.contains(contract.wireName))
        #expect(!text.contains("function_call_arguments"))
    }

    private func prepared(streaming: Bool) throws -> PreparedResponsesChatCompletionsRequest {
        try OpenAIResponsesChatCompletions.prepare(
            body: data([
                "model": "route", "input": "Find tools.", "stream": streaming,
                "tools": [
                    [
                        "type": "tool_search", "execution": "client", "description": "Find tools.",
                        "parameters": ["type": "object", "properties": ["goal": ["type": "string"]]],
                    ]
                ],
            ]),
            targetModel: "test-model"
        )
    }

    private func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
