import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Retired Responses tool identity")
struct ResponsesRetiredToolIdentityTests {
    @Test("History keeps a namespace binding after the declaration disappears")
    func retiredNamespacedTool() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: data([
                "model": "route",
                "input": [
                    [
                        "type": "function_call", "call_id": "old", "namespace": "files", "name": "read",
                        "arguments": "{}",
                    ],
                    ["type": "function_call_output", "call_id": "old", "output": "Done."],
                    ["type": "function_call", "call_id": "plain", "name": "files__read", "arguments": "{}"],
                    ["type": "function_call_output", "call_id": "plain", "output": "Plain result."],
                ],
            ]),
            targetModel: "test-model"
        )
        let root = try object(prepared.upstreamBody)
        #expect(root["tools"] == nil)
        let messages = try #require(root["messages"] as? [[String: Any]])
        let calls = try #require(messages[0]["tool_calls"] as? [[String: Any]])
        let function = try #require(calls[0]["function"] as? [String: Any])
        let wireName = try #require(function["name"] as? String)
        #expect(wireName != "files__read")
        #expect(prepared.toolBindings[wireName] == .init(namespace: "files", name: "read"))
        let response = try OpenAIResponsesChatCompletions.project(
            responseBody: data([
                "id": "chat", "created": 1,
                "choices": [
                    [
                        "finish_reason": "tool_calls",
                        "message": [
                            "content": NSNull(),
                            "tool_calls": [
                                [
                                    "type": "function", "id": "next",
                                    "function": ["name": wireName, "arguments": "{}"],
                                ]
                            ],
                        ],
                    ]
                ],
            ]),
            prepared: prepared
        )
        let output = try #require(object(response)["output"] as? [[String: Any]])
        #expect(output[0]["name"] as? String == "read")
        #expect(output[0]["namespace"] as? String == "files")
    }

    private func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func object(_ value: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: value) as? [String: Any])
    }
}
