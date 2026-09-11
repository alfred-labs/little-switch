import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses allowed tool selection")
struct ResponsesAllowedToolSelectionTests {
    @Test("Managed Responses sends only the permitted declarations", arguments: ["auto", "required"])
    func selectedDeclarations(mode: String) throws {
        let selected: [String: Any] = ["type": "function", "name": "selected", "description": "Keep this schema"]
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(
            chatJSONData([
                "model": "route", "input": "Use the selected tool",
                "tools": [selected, ["type": "function", "name": "excluded"]],
                "tool_choice": [
                    "type": "allowed_tools", "mode": mode, "tools": [["type": "function", "name": "selected"]],
                ],
            ]))
        let request = try chatJSONObject(normalized.body)
        #expect(normalized.toolNameCatalog.declared == ["selected", "excluded"])
        #expect(request["tools"] as? NSArray == [selected] as NSArray)
        #expect(request["tool_choice"] as? String == mode)
    }

    @Test("An automatic empty subset disables Responses tools")
    func emptySubset() throws {
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(
            chatJSONData([
                "model": "route", "input": "Continue without tools",
                "tools": [["type": "function", "name": "excluded"]],
                "tool_choice": ["type": "allowed_tools", "mode": "auto", "tools": []],
            ]))
        let request = try chatJSONObject(normalized.body)
        #expect(request["tools"] == nil)
        #expect(request["tool_choice"] as? String == "none")
    }

    @Test("Excluded custom declarations no longer keep freeform history active")
    func excludedCustomHistory() throws {
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(
            chatJSONData([
                "model": "route",
                "tools": [["type": "function", "name": "selected"], ["type": "custom", "name": "excluded"]],
                "tool_choice": [
                    "type": "allowed_tools", "mode": "auto", "tools": [["type": "function", "name": "selected"]],
                ],
                "input": [
                    ["type": "custom_tool_call", "call_id": "old", "name": "excluded", "input": "Original input"],
                    ["type": "custom_tool_call_output", "call_id": "old", "output": "Original output"],
                ],
            ]))
        let request = try chatJSONObject(normalized.body)
        let input = try #require(request["input"] as? [[String: Any]])
        let expected: [[String: Any]] = [
            [
                "type": "function_call", "call_id": "old", "name": "excluded",
                "arguments": "{\"input\":\"Original input\"}",
            ],
            ["type": "function_call_output", "call_id": "old", "output": "Original output"],
        ]
        #expect(input as NSArray == expected as NSArray)
    }

    @Test("An empty automatic selection is valid without a tools field")
    func noDeclarations() throws {
        var request: [String: Any] = ["tool_choice": ["type": "allowed_tools", "mode": "auto", "tools": []]]
        #expect(try ResponsesAllowedToolSelection.apply(to: &request))
        #expect(request as NSDictionary == ["tool_choice": "none"] as NSDictionary)
    }

    @Test("Malformed or impossible selections fail before changing the request")
    func invalidSelections() throws {
        let selections: [[String: Any]] = [
            [:], ["mode": "unknown", "tools": []], ["mode": "auto", "tools": "invalid"],
            ["mode": "required", "tools": []],
            ["mode": "auto", "tools": [["type": "function", "name": "missing"]]],
            ["mode": "auto", "tools": [["name": "selected"]]],
            ["mode": "auto", "tools": [["type": "unknown", "name": "selected"]]],
            ["mode": "auto", "tools": [["type": "function"]]],
        ]
        for selection in selections {
            var choice = selection
            choice["type"] = "allowed_tools"
            let original: [String: Any] = [
                "tools": [["type": "function", "name": "selected"]], "tool_choice": choice,
            ]
            var request = original
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                _ = try ResponsesAllowedToolSelection.apply(to: &request)
            }
            #expect(request as NSDictionary == original as NSDictionary)
        }
    }
}
