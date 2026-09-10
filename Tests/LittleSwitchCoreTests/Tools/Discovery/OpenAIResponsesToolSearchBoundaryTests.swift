import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI client tool search boundaries")
struct OpenAIResponsesToolSearchBoundaryTests {
    @Test("Easy input messages without a type survive client discovery adaptation")
    func untypedMessage() throws {
        let message: [String: Any] = ["role": "user", "content": "Find a reader."]
        let prepared = try #require(
            try OpenAIResponsesToolSearch.prepare(
                body: data(["model": "route", "tools": [search], "input": [message]])
            ))
        let root = try object(prepared.upstreamBody)
        #expect(root["input"] as? NSArray == [message] as NSArray)
        let tools = try #require(root["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["type"] as? String == "function")
        #expect(tools[0]["name"] as? String == prepared.contract?.wireName)
    }

    @Test("Chat reports malformed discovery catalogs as invalid client requests")
    func malformedRootFunctionName() throws {
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            try OpenAIResponsesChatCompletions.prepare(
                body: data([
                    "model": "route", "input": "Find a reader.",
                    "tools": [search, ["type": "function", "parameters": ["type": "object"]]],
                ]),
                targetModel: "test-model"
            )
        }
    }

    @Test("Loaded namespaces use the latest definition and preserve discovery order without root declarations")
    func loadedNamespaceReplacement() throws {
        let oldReader = function("read", description: "Old reader.")
        let currentReader = function("read", description: "Current reader.")
        let clock = function("clock", description: "Read the clock.")
        let oldNamespace: [String: Any] = [
            "type": "namespace", "name": "files", "description": "Old files.", "tools": [oldReader],
        ]
        let currentNamespace: [String: Any] = [
            "type": "namespace", "name": "files", "description": "Current files.", "tools": [currentReader],
        ]
        let input: [[String: Any]] = [
            ["role": "user", "content": "Find a reader and clock, then refresh the reader."],
            searchCall("first"), searchOutput("first", tools: [oldNamespace, clock]),
            searchCall("refresh"), searchOutput("refresh", tools: [currentNamespace]),
        ]
        let prepared = try #require(
            try OpenAIResponsesToolSearch.prepare(body: data(["model": "route", "tools": [], "input": input])))
        let root = try object(prepared.upstreamBody)
        var visibleReader = currentReader
        visibleReader.removeValue(forKey: "defer_loading")
        var visibleClock = clock
        visibleClock.removeValue(forKey: "defer_loading")
        let expectedNamespace: [String: Any] = [
            "type": "namespace", "name": "files", "description": "Current files.", "tools": [visibleReader],
        ]
        #expect(root["tools"] as? NSArray == [expectedNamespace, visibleClock] as NSArray)
        let replay = try #require(root["input"] as? [[String: Any]])
        #expect(replay.compactMap { $0["call_id"] as? String } == ["first", "first", "refresh", "refresh"])
        let original = try object(prepared.originalBody)
        let originalTools = try #require(original["tools"] as? [[String: Any]])
        #expect(originalTools.isEmpty)
    }

    private var search: [String: Any] {
        ["type": "tool_search", "execution": "client", "description": "Find tools.", "parameters": ["type": "object"]]
    }

    private func function(_ name: String, description: String) -> [String: Any] {
        [
            "type": "function", "name": name, "description": description,
            "parameters": ["type": "object"], "defer_loading": true,
        ]
    }

    private func searchCall(_ callID: String) -> [String: Any] {
        ["type": "tool_search_call", "execution": "client", "call_id": callID, "arguments": ["query": "reader"]]
    }

    private func searchOutput(_ callID: String, tools: [[String: Any]]) -> [String: Any] {
        ["type": "tool_search_output", "execution": "client", "call_id": callID, "tools": tools]
    }

    private func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
