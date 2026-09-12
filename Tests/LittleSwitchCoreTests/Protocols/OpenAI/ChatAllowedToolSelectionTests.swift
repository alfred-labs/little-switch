import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Chat allowed tool selection")
struct ChatAllowedToolSelectionTests {
    @Test("An empty automatic subset disables tools while required remains impossible")
    func emptySubset() throws {
        let automatic = try prepare(mode: "auto", references: [])
        let request = try chatJSONObject(automatic.upstreamBody)
        #expect(request["tools"] == nil)
        #expect(request["tool_choice"] as? String == "none")
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            _ = try prepare(mode: "required", references: [])
        }
    }

    @Test("An unavailable allowed reference cannot silently disable its constraint")
    func unavailableReference() throws {
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            _ = try prepare(mode: "auto", references: [["type": "function", "name": "missing"]])
        }
    }

    @Test("The response contract enforces the subset actually sent")
    func responseOutsideSubset() throws {
        let prepared = try prepare(mode: "required", references: [["type": "function", "name": "selected"]])
        let contract = try ProviderToolContract(wire: .chatCompletions, requestBody: prepared.upstreamBody)
        let response = try chatJSONData([
            "choices": [
                [
                    "message": [
                        "tool_calls": [
                            [
                                "id": "bad", "type": "function", "function": ["name": "excluded", "arguments": "{}"],
                            ]
                        ]
                    ]
                ]
            ]
        ])
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "excluded")) {
            try contract.validateBuffered(response)
        }
    }

    @Test("Malformed Chat selections fail closed")
    func malformedSelection() throws {
        let selections: [[String: Any]] = [
            [:], ["mode": "unknown", "tools": []],
            ["mode": "auto", "tools": [["type": "function"]]],
        ]
        for selection in selections {
            var request: [String: Any] = ["tool_choice": ["type": "allowed_tools", "allowed_tools": selection]]
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                try ChatAllowedToolSelection.apply(to: &request)
            }
        }
    }

    @Test("An empty automatic selection is valid without a tools field")
    func noDeclarations() throws {
        var request: [String: Any] = [
            "tool_choice": ["type": "allowed_tools", "allowed_tools": ["mode": "auto", "tools": []]]
        ]
        try ChatAllowedToolSelection.apply(to: &request)
        #expect(request as NSDictionary == ["tool_choice": "none"] as NSDictionary)
    }

    private func prepare(mode: String, references: [[String: Any]]) throws -> PreparedResponsesChatCompletionsRequest {
        try OpenAIResponsesChatCompletions.prepare(
            body: chatJSONData([
                "model": "route", "input": "Select a tool",
                "tools": [["type": "function", "name": "selected"], ["type": "function", "name": "excluded"]],
                "tool_choice": ["type": "allowed_tools", "mode": mode, "tools": references],
            ]), targetModel: "xlarge")
    }
}
