import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Custom history fallback validation")
struct CustomHistoryFallbackEdgeTests {
    @Test("String input and ordinary history need no conversion")
    func unrelatedInput() throws {
        for root: [String: Any] in [
            ["model": "route", "input": "Hello"],
            ["model": "route", "input": [["type": "message", "role": "user", "content": "Hello"]]],
        ] {
            #expect(try ResponsesCustomToolHistory.normalized(root).request as NSDictionary == root as NSDictionary)
        }
    }

    @Test("A flat active custom tool and its result stay canonical")
    func flatActiveCustomTool() throws {
        var root = try chatJSONObject(customHistoryFallbackRequest())
        root["tools"] = [["type": "custom", "name": "patch"]]
        var input = try #require(root["input"] as? [[String: Any]])
        input[0].removeValue(forKey: "namespace")
        root["input"] = input
        #expect(try ResponsesCustomToolHistory.normalized(root).request as NSDictionary == root as NSDictionary)
    }

    @Test("Malformed declarations do not make retired history callable")
    func ignoredDeclarations() throws {
        var root = try chatJSONObject(customHistoryFallbackRequest())
        let tools: [[String: Any]] = [
            ["type": "custom"], ["type": "function", "name": "ordinary", "parameters": [:]],
            ["type": "namespace", "name": "workspace"],
            [
                "type": "namespace", "name": "workspace",
                "tools": [["type": "custom"], ["type": "function", "name": "patch", "parameters": [:]]],
            ],
        ]
        root["tools"] = tools
        let normalized = try ResponsesCustomToolHistory.normalized(root).request
        let outputTools = try #require(normalized["tools"] as? [[String: Any]])
        #expect(try chatJSONData(outputTools) == chatJSONData(tools))
        let input = try #require(normalized["input"] as? [[String: Any]])
        let source = try #require(root["input"] as? [[String: Any]])
        #expect(try historyArchiveItem(WireJSONCompatibility.value(input[0])) == WireJSONCompatibility.value(source[0]))
        #expect(try historyArchiveItem(WireJSONCompatibility.value(input[1])) == WireJSONCompatibility.value(source[1]))
    }

    @Test("Malformed custom calls and results fail before an upstream request")
    func malformedHistory() throws {
        let invalid: [[String: Any]] = [
            ["type": "custom_tool_call", "name": "patch", "input": "x"],
            ["type": "custom_tool_call", "call_id": "call", "input": "x"],
            ["type": "custom_tool_call", "call_id": "call", "name": "patch", "input": 1],
            ["type": "custom_tool_call_output", "output": "x"],
            ["type": "custom_tool_call_output", "call_id": "call"],
        ]
        for item in invalid {
            let root: [String: Any] = ["model": "route", "input": [item]]
            #expect(throws: ResponsesCustomToolHistory.Error.invalidHistory) {
                _ = try ResponsesCustomToolHistory.normalized(root)
            }
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                _ = try OpenAIResponsesChatCompletions.prepare(body: chatJSONData(root), targetModel: "provider-model")
            }
        }
    }
}
