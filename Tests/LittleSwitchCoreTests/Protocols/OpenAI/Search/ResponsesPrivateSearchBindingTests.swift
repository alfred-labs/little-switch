import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Responses private search binding")
struct ResponsesPrivateSearchBindingTests {
    @Test("Search reserves a fresh name across declared and retired ordinary functions")
    func reservesAgainstDeclarationsAndHistory() throws {
        let base = "__little_switch_web_search"
        let history: [[String: Any]] = [
            ["type": "message", "role": "user", "content": "Continue the search."],
            ["type": "function_call", "name": "\(base)_2", "call_id": "old", "arguments": "{}"],
            ["type": "function_call_output", "call_id": "old", "output": "Previous client result."],
        ]
        let request = try data([
            "model": "route", "input": history,
            "tools": [["type": "web_search"], function("web_search"), function(base)],
            "tool_choice": ["type": "web_search"],
        ])
        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: request, targetModel: "test-model", configuration: WebSearchConfiguration(provider: .firecrawl)
            ))
        let root = try #require(JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any])
        let tools = try #require(root["tools"] as? [[String: Any]])
        #expect(prepared.privateToolName == "\(base)_3")
        #expect(tools.compactMap { $0["name"] as? String } == ["\(base)_3", "web_search", base])
        #expect(Array(tools.dropFirst()) as NSArray == [function("web_search"), function(base)] as NSArray)
        #expect(root["input"] as? NSArray == history as NSArray)
        #expect(root["tool_choice"] as? NSDictionary == ["type": "function", "name": "\(base)_3"] as NSDictionary)
    }

    private func function(_ name: String) -> [String: Any] {
        ["type": "function", "name": name, "parameters": ["type": "object"]]
    }

    private func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
