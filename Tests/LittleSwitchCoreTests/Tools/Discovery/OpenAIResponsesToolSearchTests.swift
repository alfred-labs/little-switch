import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI client tool search")
struct OpenAIResponsesToolSearchTests {
    @Test("Client tool search reaches Chat providers as an ordinary function")
    func clientSearchDeclaration() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: request(tools: [searchTool]),
            targetModel: "test-model"
        )
        let root = try object(prepared.upstreamBody)
        let tools = try #require(root["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        let function = try #require(tools.first?["function"] as? [String: Any])
        #expect(function["description"] as? String == "Find tools for the task.")
        #expect((function["parameters"] as? NSDictionary) == (searchTool["parameters"] as? NSDictionary))
    }

    @Test("Undiscovered deferred definitions stay out of the inference request")
    func deferredDefinitions() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: request(tools: [searchTool, function("hidden", deferred: true), function("visible")]),
            targetModel: "test-model"
        )
        let root = try object(prepared.upstreamBody)
        let tools = try #require(root["tools"] as? [[String: Any]])
        let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        #expect(names.count == 2)
        #expect(names.contains("visible"))
        #expect(!names.contains("hidden"))
    }

    @Test("Search results promote definitions and replay without a current search declaration")
    func historyPromotesTools() throws {
        let input: [[String: Any]] = [
            ["type": "message", "role": "user", "content": "Find the reader."],
            [
                "type": "tool_search_call", "execution": "client", "call_id": "search_1",
                "arguments": ["goal": "reader"],
            ],
            [
                "type": "tool_search_output", "execution": "client", "call_id": "search_1", "status": "completed",
                "tools": [function("read_file", deferred: true)],
            ],
            ["type": "function_call", "call_id": "read_1", "name": "read_file", "arguments": "{}"],
            ["type": "function_call_output", "call_id": "read_1", "output": "Read."],
        ]
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: request(tools: [], input: input),
            targetModel: "test-model"
        )
        let root = try object(prepared.upstreamBody)
        let tools = try #require(root["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect((tools[0]["function"] as? [String: Any])?["name"] as? String == "read_file")
        let messages = try #require(root["messages"] as? [[String: Any]])
        #expect(messages.compactMap { $0["role"] as? String } == ["user", "assistant", "tool", "assistant", "tool"])
        #expect(messages[2]["tool_call_id"] as? String == "search_1")
        #expect((messages[2]["content"] as? String)?.contains("read_file") == true)
        #expect(messages[4]["content"] as? String == "Read.")
    }

    @Test("Provider search calls restore the client tool search output contract")
    func restoresSearchCall() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: request(tools: [searchTool]),
            targetModel: "test-model"
        )
        let upstream = try object(prepared.upstreamBody)
        let tools = try #require(upstream["tools"] as? [[String: Any]])
        let function = try #require(tools.first?["function"] as? [String: Any])
        let wireName = try #require(function["name"] as? String)
        let response = try OpenAIResponsesChatCompletions.project(
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
                                    "function": ["name": wireName, "arguments": "{\"goal\":\"read files\"}"],
                                ]
                            ],
                        ],
                    ]
                ],
            ]),
            prepared: prepared
        )
        let root = try object(response)
        let output = try #require(root["output"] as? [[String: Any]])
        #expect(
            output as NSArray == [
                [
                    "id": "fc_resp_chat_search_0", "type": "tool_search_call", "execution": "client",
                    "call_id": "call_1", "status": "completed", "arguments": ["goal": "read files"],
                ]
            ] as NSArray)
        #expect(root["tools"] as? NSArray == [searchTool] as NSArray)
    }

    private var searchTool: [String: Any] {
        [
            "type": "tool_search", "execution": "client", "description": "Find tools for the task.",
            "parameters": [
                "type": "object", "properties": ["goal": ["type": "string"]],
                "required": ["goal"], "additionalProperties": false,
            ],
        ]
    }

    private func function(_ name: String, deferred: Bool = false) -> [String: Any] {
        ["type": "function", "name": name, "parameters": ["type": "object"], "defer_loading": deferred]
    }

    private func request(tools: [[String: Any]], input: Any = "Find the right tool.") throws -> Data {
        try data(["model": "route", "input": input, "tools": tools])
    }

    private func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func object(_ value: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: value) as? [String: Any])
    }
}
