import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Chat tool-output image association")
struct ResponsesChatCompletionsToolOutputTests {
    @Test("Tool images become real user attachments after every parallel result", arguments: [false, true])
    func parallelImages(custom: Bool) throws {
        let callType = custom ? "custom_tool_call" : "function_call"
        let outputType = custom ? "custom_tool_call_output" : "function_call_output"
        let input: [[String: Any]] = [
            ["type": callType, "call_id": "a", "name": "read", custom ? "input" : "arguments": "{}"],
            ["type": "function_call", "call_id": "b", "name": "read", "arguments": "{}"],
            [
                "type": outputType, "call_id": "a",
                "output": [
                    ["type": "input_text", "text": "Visible output"],
                    ["type": "input_image", "image_url": Self.imageURL, "detail": "low"],
                ],
            ],
            ["type": "function_call_output", "call_id": "b", "output": "B"],
        ]
        var messages: [[String: Any]] = []
        _ = try ResponsesChatCompletionsHistory.append(input, to: &messages, bindings: [:])
        let kind = custom ? "custom" : "function"
        let expected: [[String: Any]] = [
            [
                "role": "assistant", "content": NSNull(),
                "tool_calls": [
                    ["id": "a", "type": kind, kind: ["name": "read", custom ? "input" : "arguments": "{}"]],
                    ["id": "b", "type": "function", "function": ["name": "read", "arguments": "{}"]],
                ],
            ],
            ["role": "tool", "tool_call_id": "a", "content": "Visible output"],
            ["role": "tool", "tool_call_id": "b", "content": "B"],
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": "Image from tool call a"],
                    ["type": "image_url", "image_url": ["url": Self.imageURL, "detail": "low"]],
                ],
            ],
        ]
        #expect(messages as NSArray == expected as NSArray)
    }

    @Test("Image-only output stays structured; opaque JSON output stays text")
    func outputKinds() throws {
        let image = try ResponsesChatCompletionsToolOutput.project(item: [
            "call_id": "a", "output": [["type": "input_image", "image_url": Self.imageURL]],
        ])
        #expect(
            image.toolMessage as NSDictionary == [
                "role": "tool", "tool_call_id": "a", "content": "[Image attached separately.]",
            ] as NSDictionary)
        #expect(image.imageMessages.count == 1)
        let json = try ResponsesChatCompletionsToolOutput.project(item: ["call_id": "a", "output": ["value": 42]])
        #expect(
            json.toolMessage as NSDictionary == [
                "role": "tool", "tool_call_id": "a", "content": #"{"value":42}"#,
            ] as NSDictionary)
        #expect(json.imageMessages.isEmpty)
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            try ResponsesChatCompletionsToolOutput.project(item: [
                "call_id": "a", "output": [["type": "input_image", "file_id": "file-image"]],
            ])
        }
    }

    @Test("An incomplete parallel exchange cannot silently drop or misplace an image")
    func incompleteParallelExchange() {
        let input: [[String: Any]] = [
            ["type": "function_call", "call_id": "a", "name": "read", "arguments": "{}"],
            ["type": "function_call", "call_id": "b", "name": "read", "arguments": "{}"],
            [
                "type": "function_call_output", "call_id": "a",
                "output": [["type": "input_image", "image_url": Self.imageURL]],
            ],
        ]
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            var messages: [[String: Any]] = []
            _ = try ResponsesChatCompletionsHistory.append(input, to: &messages, bindings: [:])
        }
    }

    private static let imageURL = "data:image/png;base64,aGVsbG8="
}
