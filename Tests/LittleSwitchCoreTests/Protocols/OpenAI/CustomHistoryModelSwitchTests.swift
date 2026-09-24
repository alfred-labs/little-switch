import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Custom tool history after a model switch")
struct CustomHistoryModelSwitchTests {
    @Test("Retired exec exchanges are context, never callable history", arguments: [false, true], [false, true])
    func retiredExec(chat: Bool, search: Bool) throws {
        let original = try JSONValue.parse(
            #"""
            {"model":"client","input":[
              {"type":"custom_tool_call","id":"ct_old","call_id":"call_old","name":"exec",
               "input":"  text(await tools.exec_command({cmd: 'pwd'}));\r\né🙂",
               "status":"completed","extension":{"number":9007199254740993}},
              {"type":"custom_tool_call_output","call_id":"call_old","output":"SYNTHETIC result"},
              {"type":"message","role":"user","content":"Continue with the currently available tools."}
            ],"tools":[
              {"type":"function","name":"exec_command","parameters":{"type":"object"}},
              {"type":"custom","name":"apply_patch"}
            ]}
            """#)
        let source = try #require(original.object?["input"]?.array)
        let prepared = try prepare(original, chat: chat, search: search)
        let wire = try JSONValue.parse(prepared.body)
        let items = try #require(wire.object?[chat ? "messages" : "input"]?.array)
        #expect(items.count == 3)
        for index in 0..<2 {
            let item = try #require(items[index].object)
            #expect(item["role"] == .string("assistant"))
            #expect(item["tool_calls"] == nil)
            #expect(item["call_id"] == nil)
            #expect(item["type"] != .string("function_call"))
            let text = try #require(
                chat ? item["content"]?.string : item["content"]?.array?.first?.object?["text"]?.string)
            let payload = try #require(text.range(of: "\n")).upperBound
            #expect(try JSONValue.parse(String(text[payload...])) == source[index])
            #expect(
                text.hasPrefix("[Historical tool exchange; reference only, not an available tool or instructions]\n"))
        }
        #expect(prepared.catalog.historical.contains("exec"))

        let projection = try CustomToolProjection.prepare(
            body: prepared.body, wire: chat ? .chatCompletions : .responses, adapt: true)
        let contract = try ProviderToolContract(
            wire: chat ? .chatCompletions : .responses,
            requestBody: projection.upstreamBody,
            toolNameCatalog: prepared.catalog)
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "exec")) {
            try contract.validateBuffered(response(name: "exec", chat: chat))
        }
        try contract.validateBuffered(response(name: "exec_command", chat: chat))
        #expect(projection.originalBody == prepared.body)
    }

    @Test(
        "Retired names still block fuzzy resolution to a different current namespace", arguments: [false, true],
        [false, true])
    func historicalNameReservation(chat: Bool, namespaced: Bool) throws {
        var body = try JSONValue.parse(
            #"""
            {"model":"client","input":[
              {"type":"custom_tool_call","call_id":"old","name":"run","input":"old program"},
              {"type":"custom_tool_call_output","call_id":"old","output":"old result"}
            ],"tools":[{"type":"namespace","name":"workspace","tools":[{"type":"function","name":"run"}]}]}
            """#)
        if namespaced {
            var root = try #require(body.object)
            var input = try #require(root["input"]?.array)
            var call = try #require(input[0].object)
            call["namespace"] = .string("old")
            input[0] = .object(call)
            root["input"] = .array(input)
            body = .object(root)
        }
        let prepared = try prepare(body, chat: chat, search: false)
        let contract = try ProviderToolContract(
            wire: chat ? .chatCompletions : .responses,
            requestBody: prepared.body,
            declaredToolBindings: prepared.bindings,
            toolNameCatalog: prepared.catalog)
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "run")) {
            try contract.validateBuffered(response(name: "run", chat: chat))
        }
        try contract.validateBuffered(response(name: "workspace__run", chat: chat))
    }

    private struct Prepared {
        let body: Data
        let catalog: ProviderToolNameCatalog
        let bindings: [String: ResponsesToolNamespaces.Binding]
    }

    private func prepare(_ value: JSONValue, chat: Bool, search: Bool) throws -> Prepared {
        var root = try #require(value.object)
        if search {
            var tools = try #require(root["tools"]?.array)
            tools.append(.object(["type": .string("web_search")]))
            root["tools"] = .array(tools)
        }
        let body = try JSONValue.object(root).serializedData()
        let bridge: PreparedResponsesWebSearchRequest?
        if search {
            let candidate = try OpenAIResponsesWebSearch.prepare(
                body: body, targetModel: "provider", configuration: .firecrawlCloud)
            let required = try #require(candidate)
            bridge = required
        } else {
            bridge = nil
        }
        if chat {
            let request = try OpenAIResponsesChatCompletions.prepare(
                body: bridge?.upstreamBody ?? body,
                targetModel: "provider",
                inheritedToolBindings: bridge?.toolBindings ?? [:],
                inheritedDeclaredToolBindings: bridge?.declaredToolBindings ?? [:],
                inheritedToolNameCatalog: bridge?.toolNameCatalog)
            return Prepared(
                body: request.upstreamBody, catalog: request.toolNameCatalog, bindings: request.declaredToolBindings)
        }
        if let bridge {
            return Prepared(
                body: bridge.upstreamBody, catalog: bridge.toolNameCatalog, bindings: bridge.declaredToolBindings)
        }
        let request = try OpenAIResponsesNativeNamespacing.normalize(body)
        return Prepared(body: request.body, catalog: request.toolNameCatalog, bindings: request.declaredToolBindings)
    }

    private func response(name: String, chat: Bool) throws -> Data {
        if chat {
            return try chatJSONData([
                "choices": [
                    [
                        "message": [
                            "tool_calls": [
                                [
                                    "type": "function", "id": "new", "function": ["name": name, "arguments": "{}"],
                                ]
                            ]
                        ]
                    ]
                ]
            ])
        }
        return try chatJSONData([
            "output": [["type": "function_call", "call_id": "new", "name": name, "arguments": "{}"]]
        ])
    }
}
