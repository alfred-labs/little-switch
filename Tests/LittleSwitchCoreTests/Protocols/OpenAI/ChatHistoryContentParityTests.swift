import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Chat assistant content continuity")
struct ChatHistoryContentParityTests {
    @Test("Text and refusal fragments stay in the assistant turn that owns its tool calls")
    func textAndRefusalFragments() throws {
        let input: [[String: Any]] = [
            ["type": "message", "role": "assistant", "content": "First fragment"],
            call,
            [
                "type": "message", "role": "assistant",
                "content": [
                    ["type": "output_text", "text": "Second fragment"],
                    ["type": "refusal", "refusal": "First refusal"],
                ],
            ],
            ["type": "message", "role": "assistant", "content": [["type": "refusal", "refusal": "Second refusal"]]],
            result,
        ]
        let expected: [[String: Any]] = [
            [
                "role": "assistant", "content": "First fragment\nSecond fragment",
                "refusal": "First refusal\nSecond refusal", "tool_calls": [chatCall],
            ],
            chatResult,
        ]
        #expect(try messages(input) as NSArray == expected as NSArray)
    }

    @Test("Refusals require an assistant and a string payload", arguments: [false, true])
    func invalidRefusal(wrongRole: Bool) throws {
        let refusal: Any = wrongRole ? "Refusal" : 7
        let body = try chatJSONData([
            "model": "route",
            "input": [
                [
                    "type": "message", "role": wrongRole ? "user" : "assistant",
                    "content": [["type": "refusal", "refusal": refusal]],
                ]
            ],
        ])
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            _ = try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "xlarge")
        }
    }

    @Test("A historical content part without a type is rejected without dropping its payload")
    func missingPartType() throws {
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            _ = try messages([
                ["type": "message", "role": "assistant", "content": [["text": "Preserve this payload"]]]
            ])
        }
    }

    @Test("Multipart content retains its position between text fragments")
    func multipartFragments() throws {
        let image = "data:image/png;base64,aGVsbG8="
        let input: [[String: Any]] = [
            ["type": "message", "role": "assistant", "content": "Image context"],
            call,
            [
                "type": "message", "role": "assistant",
                "content": [
                    ["type": "input_image", "image_url": image],
                    ["type": "output_text", "text": "Caption"],
                ],
            ],
            ["type": "message", "role": "assistant", "content": "Closing"],
            result,
        ]
        let expected: [[String: Any]] = [
            [
                "role": "assistant", "tool_calls": [chatCall],
                "content": [
                    ["type": "text", "text": "Image context"],
                    ["type": "image_url", "image_url": ["url": image]],
                    ["type": "text", "text": "Caption"],
                    ["type": "text", "text": "Closing"],
                ],
            ],
            chatResult,
        ]
        #expect(try messages(input) as NSArray == expected as NSArray)
    }

    private var call: [String: Any] {
        ["type": "function_call", "call_id": "inspect", "name": "inspect", "arguments": "{}"]
    }

    private var result: [String: Any] {
        ["type": "function_call_output", "call_id": "inspect", "output": "Done"]
    }

    private var chatCall: [String: Any] {
        ["id": "inspect", "type": "function", "function": ["name": "inspect", "arguments": "{}"]]
    }

    private var chatResult: [String: Any] {
        ["role": "tool", "tool_call_id": "inspect", "content": "Done"]
    }

    private func messages(_ input: [[String: Any]]) throws -> [[String: Any]] {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: chatJSONData(["model": "route", "input": input]), targetModel: "xlarge")
        return try chatReasoningMessages(prepared.upstreamBody)
    }
}
