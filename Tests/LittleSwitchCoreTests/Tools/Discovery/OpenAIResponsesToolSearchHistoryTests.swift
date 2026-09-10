import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI client tool search history")
struct OpenAIResponsesToolSearchHistoryTests {
    @Test("Developer additional_tools promotes definitions at its original history position")
    func additionalTools() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: data([
                "model": "route", "tools": [],
                "input": [
                    ["type": "message", "role": "user", "content": "Find tools."],
                    ["type": "additional_tools", "role": "developer", "tools": [function("read_file")]],
                    ["type": "function_call", "call_id": "read", "name": "read_file", "arguments": "{}"],
                    ["type": "function_call_output", "call_id": "read", "output": "Done."],
                ],
            ]),
            targetModel: "test-model"
        )
        let root = try object(prepared.upstreamBody)
        let messages = try #require(root["messages"] as? [[String: Any]])
        #expect(messages.compactMap { $0["role"] as? String } == ["user", "system", "assistant", "tool"])
        #expect((messages[1]["content"] as? String)?.contains("read_file") == true)
        let tools = try #require(root["tools"] as? [[String: Any]])
        #expect((tools.first?["function"] as? [String: Any])?["name"] as? String == "read_file")
        #expect(prepared.toolSearchContract == nil)
    }

    @Test("The most recently loaded definition wins when root declarations omit it")
    func refreshedDefinition() throws {
        var first = function("read_file")
        first["description"] = "Old definition."
        var second = first
        second["description"] = "Current definition."
        let prepared = try OpenAIResponsesToolSearch.prepare(
            body: data([
                "model": "route", "input": [searchOutput("a", tools: [first]), searchOutput("b", tools: [second])],
            ]))
        let root = try object(#require(prepared).upstreamBody)
        let tools = try #require(root["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["description"] as? String == "Current definition.")
    }

    @Test("Loaded namespaces retain identity and only reveal discovered functions")
    func loadedNamespace() throws {
        let rootNamespace: [String: Any] = [
            "type": "namespace", "name": "files", "tools": [function("read_file"), function("write_file")],
        ]
        let loadedNamespace: [String: Any] = ["type": "namespace", "name": "files", "tools": [function("read_file")]]
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: data([
                "model": "route", "tools": [rootNamespace],
                "tool_choice": ["type": "function", "namespace": "files", "name": "read_file"],
                "input": [
                    searchOutput("a", tools: [loadedNamespace]),
                    [
                        "type": "function_call", "call_id": "read", "namespace": "files", "name": "read_file",
                        "arguments": "{}",
                    ],
                    ["type": "function_call_output", "call_id": "read", "output": "Done."],
                ],
            ]),
            targetModel: "test-model"
        )
        let root = try object(prepared.upstreamBody)
        let tools = try #require(root["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect((tools[0]["function"] as? [String: Any])?["name"] as? String == "files__read_file")
        #expect(prepared.toolBindings["files__read_file"] == .init(namespace: "files", name: "read_file"))
        #expect(
            root["tool_choice"] as? NSDictionary == ["type": "function", "function": ["name": "files__read_file"]]
                as NSDictionary)
    }

    private func function(_ name: String) -> [String: Any] {
        ["type": "function", "name": name, "parameters": ["type": "object"], "defer_loading": true]
    }

    private func searchOutput(_ callID: String, tools: [[String: Any]]) -> [String: Any] {
        ["type": "tool_search_output", "execution": "client", "call_id": callID, "tools": tools]
    }

    private func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func object(_ value: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: value) as? [String: Any])
    }
}
