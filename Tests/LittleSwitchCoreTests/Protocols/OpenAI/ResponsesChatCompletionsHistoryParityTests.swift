import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses to Chat history parity")
struct ChatCompletionsHistoryParityTests {
    @Test("Restored reasoning starts after the synthetic compacted summary")
    func reasoningStartsNewAssistantTurn() throws {
        let projected = try chatReasoningProjection(fields: ["reasoning_content": "State for the original answer"])
        let history: [[String: Any]] =
            [
                ["type": "message", "role": "assistant", "content": "Synthetic compacted summary"]
            ] + (try chatReasoningOutput(projected)) + [["type": "message", "role": "user", "content": "Continue"]]
        let expected: [[String: Any]] = [
            ["role": "assistant", "content": "Synthetic compacted summary"],
            ["role": "assistant", "content": "Visible answer", "reasoning_content": "State for the original answer"],
            ["role": "user", "content": "Continue"],
        ]
        #expect(try messages(history) as NSArray == expected as NSArray)
    }

    @Test("Refusal history remains a structured assistant refusal")
    func refusalHistory() throws {
        let input: [[String: Any]] = [
            [
                "type": "message", "role": "assistant",
                "content": [["type": "refusal", "refusal": "I cannot provide that."]],
            ],
            ["type": "message", "role": "user", "content": "Try a permitted alternative"],
        ]
        let expected: [[String: Any]] = [
            ["role": "assistant", "content": NSNull(), "refusal": "I cannot provide that."],
            ["role": "user", "content": "Try a permitted alternative"],
        ]
        #expect(try messages(input) as NSArray == expected as NSArray)
    }

    @Test("Image requests apply the same completion reserve policy on both provider APIs")
    func imageBudgetParity() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "route", "reasoning": ["effort": "high"],
            "input": [
                [
                    "type": "message", "role": "user",
                    "content": [["type": "input_image", "image_url": "data:image/png;base64,aGVsbG8="]],
                ]
            ],
        ])
        let native = try OpenAIResponsesNativeNamespacing.normalize(body)
        let chat = try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "xlarge")
        let nativeRequest = try #require(JSONSerialization.jsonObject(with: native.body) as? [String: Any])
        let chatRequest = try #require(JSONSerialization.jsonObject(with: chat.upstreamBody) as? [String: Any])
        #expect(chatRequest["max_tokens"] as? Int == nativeRequest["max_output_tokens"] as? Int)
        #expect(chatRequest["reasoning_effort"] == nil)
    }

    @Test("Parallel calls share one assistant message and retain each result")
    func parallelToolHistory() throws {
        let input: [[String: Any]] = [
            ["type": "message", "role": "user", "content": "Inspect both"],
            ["type": "message", "role": "assistant", "content": "I will inspect both."],
            ["type": "function_call", "call_id": "a", "name": "read", "arguments": "{\"path\":\"a\"}"],
            ["type": "function_call", "call_id": "b", "name": "read", "arguments": "{\"path\":\"b\"}"],
            ["type": "function_call_output", "call_id": "b", "output": "B"],
            ["type": "function_call_output", "call_id": "a", "output": "A"],
            ["type": "message", "role": "assistant", "content": "Both inspected."],
            ["type": "message", "role": "user", "content": "Inspect C"],
            ["type": "function_call", "call_id": "c", "name": "read", "arguments": "{\"path\":\"c\"}"],
            ["type": "function_call_output", "call_id": "c", "output": ["value": "C"]],
        ]
        let expected: [[String: Any]] = [
            ["role": "user", "content": "Inspect both"],
            [
                "role": "assistant", "content": "I will inspect both.",
                "tool_calls": [
                    functionCall("a", arguments: "{\"path\":\"a\"}"),
                    functionCall("b", arguments: "{\"path\":\"b\"}"),
                ],
            ],
            ["role": "tool", "tool_call_id": "b", "content": "B"],
            ["role": "tool", "tool_call_id": "a", "content": "A"],
            ["role": "assistant", "content": "Both inspected."],
            ["role": "user", "content": "Inspect C"],
            [
                "role": "assistant", "content": NSNull(),
                "tool_calls": [functionCall("c", arguments: "{\"path\":\"c\"}")],
            ],
            ["role": "tool", "tool_call_id": "c", "content": "{\"value\":\"C\"}"],
        ]
        #expect(try messages(input) as NSArray == expected as NSArray)
    }

    @Test("Custom and function calls retain structured identity in the same turn")
    func customToolHistory() throws {
        let input: [[String: Any]] = [
            ["type": "function_call", "call_id": "f", "name": "read", "arguments": "{}"],
            [
                "type": "custom_tool_call", "call_id": "c", "name": "apply_patch",
                "input": "*** Begin Patch\n*** End Patch",
            ],
            ["type": "custom_tool_call_output", "call_id": "c", "output": "Done"],
            ["type": "function_call_output", "call_id": "f", "output": "Found"],
            ["type": "message", "role": "user", "content": "Continue"],
        ]
        let expected: [[String: Any]] = [
            [
                "role": "assistant", "content": NSNull(),
                "tool_calls": [
                    functionCall("f", arguments: "{}"),
                    [
                        "id": "c", "type": "custom",
                        "custom": ["name": "apply_patch", "input": "*** Begin Patch\n*** End Patch"],
                    ],
                ],
            ],
            ["role": "tool", "tool_call_id": "c", "content": "Done"],
            ["role": "tool", "tool_call_id": "f", "content": "Found"],
            ["role": "user", "content": "Continue"],
        ]
        let tools: [[String: Any]] = [["type": "custom", "name": "apply_patch", "format": ["type": "text"]]]
        #expect(try messages(input, tools: tools) as NSArray == expected as NSArray)
    }

    private func messages(_ input: [[String: Any]], tools: [[String: Any]] = []) throws -> [[String: Any]] {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: JSONSerialization.data(withJSONObject: ["model": "route", "input": input, "tools": tools]),
            targetModel: "xlarge"
        )
        let request = try #require(JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any])
        return try #require(request["messages"] as? [[String: Any]])
    }

    private func functionCall(_ id: String, arguments: String) -> [String: Any] {
        ["id": id, "type": "function", "function": ["name": "read", "arguments": arguments]]
    }
}
