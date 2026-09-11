import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI client tool search validation")
struct OpenAIResponsesToolSearchValidationTests {
    @Test("Unrelated requests remain byte-identical")
    func transparentRequests() throws {
        let body = Data(
            #"{ "model": "route", "input": "Hello", "tools": [{"type":"function","name":"ToolSearch","parameters":{}}] }"#
                .utf8)
        #expect(try OpenAIResponsesToolSearch.prepare(body: body) == nil)
    }

    @Test("Chat preserves free-form declarations through namespace flattening", arguments: [false, true])
    func chatCustomTools(_ namespaced: Bool) throws {
        let custom: [String: Any] = ["type": "custom", "name": "free_form"]
        let declaration = namespaced ? ["type": "namespace", "name": "files", "tools": [custom]] : custom
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: data(["model": "route", "input": "Hello", "tools": [declaration]]),
            targetModel: "test-model")
        let root = try #require(JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any])
        let tools = try #require(root["tools"] as? [[String: Any]])
        let name = namespaced ? "files__free_form" : "free_form"
        var expected = ["name": name]
        if namespaced {
            expected["description"] = "Call this tool by its exact name \"files__free_form\". [files]"
        }
        #expect(tools as NSArray == [["type": "custom", "custom": expected]] as NSArray)
    }

    @Test("The search transport name cannot collide with ordinary tools or replayed calls")
    func reservedIdentity() throws {
        let base = "little_switch_tool_search"
        let body = try data([
            "model": "route", "tools": [search, function(base)],
            "input": [
                ["type": "function_call", "call_id": "a", "name": "\(base)_2", "arguments": "{}"],
                ["type": "function_call", "call_id": "b", "namespace": "files", "name": "read", "arguments": "{}"],
                ["type": "function_call"],
            ],
            "tool_choice": ["type": "tool_search"],
        ])
        let prepared = try #require(try OpenAIResponsesToolSearch.prepare(body: body))
        let contract = try #require(prepared.contract)
        #expect(contract.wireName == "\(base)_3")
        let root = try #require(JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any])
        #expect(
            root["tool_choice"] as? NSDictionary == ["type": "function", "name": contract.wireName] as NSDictionary)
        #expect(prepared.originalBody == body)
        #expect(try OpenAIResponsesToolSearch.prepare(body: body) == prepared)
        let ordinary: [String: Any] = ["type": "function_call", "name": base, "call_id": "normal", "arguments": "{}"]
        #expect(try contract.projectItem(ordinary) as NSDictionary == ordinary as NSDictionary)
        let namespaced: [String: Any] = ["type": "function_call", "namespace": "other", "name": contract.wireName]
        #expect(try contract.projectItem(namespaced) as NSDictionary == namespaced as NSDictionary)
    }

    @Test(
        "Malformed client discovery inputs are rejected",
        arguments: [
            "root", "duplicate", "description", "parameters", "loaded_tools", "call_id", "arguments",
            "deferred", "namespace_name", "namespace_tools", "loaded_name", "loaded_parameters", "loaded_type",
            "additional_role", "additional_tools", "output_status", "forced_without_declaration", "root_custom",
        ])
    func malformedRequests(_ variant: String) throws {
        var declaration = search
        var declared = function("visible")
        var output: [String: Any] = [
            "type": "tool_search_output", "execution": "client", "call_id": "search", "tools": [],
        ]
        var call: [String: Any] = [
            "type": "tool_search_call", "execution": "client", "call_id": "search", "arguments": [:],
        ]
        var root: [String: Any] = ["model": "route", "input": "Hello", "tools": [search]]
        switch variant {
        case "root":
            #expect(throws: OpenAIResponsesToolSearch.Error.invalidRequest) {
                try OpenAIResponsesToolSearch.prepare(body: Data("[]".utf8))
            }
            return
        case "duplicate": root["tools"] = [search, search]
        case "description":
            declaration["description"] = NSNull()
            root["tools"] = [declaration]
        case "parameters":
            declaration["parameters"] = "bad"
            root["tools"] = [declaration]
        case "loaded_tools":
            output["tools"] = NSNull()
            root["input"] = [output]
        case "call_id":
            call["call_id"] = ""
            root["input"] = [call]
        case "arguments":
            call["arguments"] = "{}"
            root["input"] = [call]
        case "deferred":
            declared["defer_loading"] = "true"
            root["tools"] = [search, declared]
        case "namespace_name": root["tools"] = [search, ["type": "namespace", "tools": []]]
        case "namespace_tools":
            output["tools"] = [["type": "namespace", "name": "files"]]
            root["input"] = [output]
        case "loaded_name":
            declared["name"] = ""
            output["tools"] = [declared]
            root["input"] = [output]
        case "loaded_parameters":
            declared["parameters"] = NSNull()
            output["tools"] = [declared]
            root["input"] = [output]
        case "loaded_type":
            output["tools"] = [["type": "mcp", "server_url": "https://example.invalid"]]
            root["input"] = [output]
        case "additional_role": root["input"] = [["type": "additional_tools", "role": "user", "tools": []]]
        case "additional_tools": root["input"] = [["type": "additional_tools", "role": "developer"]]
        case "output_status":
            output["status"] = "invalid"
            root["input"] = [output]
        case "root_custom":
            root["tools"] = [search, ["type": "custom", "name": "free_form"]]
        default:
            root["tools"] = []
            root["input"] = [output]
            root["tool_choice"] = ["type": "tool_search"]
        }
        #expect(throws: OpenAIResponsesToolSearch.Error.invalidRequest) {
            try OpenAIResponsesToolSearch.prepare(body: data(root))
        }
    }

    @Test("Invalid provider search arguments never reach the client", arguments: ["", "bad", "[]", "1", "null"])
    func invalidProviderArguments(_ arguments: String) throws {
        let contract = ResponsesClientToolSearchContract(wireName: "search")
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try contract.projectItem([
                "type": "function_call", "name": "search", "id": "fc", "call_id": "call", "arguments": arguments,
            ])
        }
    }

    @Test("Projection validates identity and supplies completed status")
    func providerIdentity() throws {
        let contract = ResponsesClientToolSearchContract(wireName: "search")
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try contract.projectItem(["type": "function_call", "name": "search", "arguments": "{}"])
        }
        let valid: [String: Any] = [
            "type": "function_call", "name": "search", "id": "fc", "call_id": "call", "arguments": "{}",
        ]
        let item = try contract.projectItem(valid)
        #expect(item["status"] as? String == "completed")
        #expect(try OpenAIResponsesPublicSanitizer.item(item) as NSDictionary == item as NSDictionary)
        var malformed = item
        malformed["execution"] = "server"
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesPublicSanitizer.item(malformed)
        }
    }

    private var search: [String: Any] {
        ["type": "tool_search", "execution": "client", "description": "Find tools.", "parameters": ["type": "object"]]
    }

    private func function(_ name: String) -> [String: Any] {
        ["type": "function", "name": name, "parameters": ["type": "object"]]
    }

    private func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
