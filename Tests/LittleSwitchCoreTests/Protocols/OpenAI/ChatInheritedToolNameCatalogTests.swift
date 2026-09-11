import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Chat inherited tool name reservations")
struct ChatInheritedToolNameCatalogTests {
    @Test(
        "Inherited excluded and historical names reserve identity without authorizing calls",
        arguments: ["run", "retired_run"])
    func inheritedReservations(_ name: String) throws {
        let wireName = "workspace__run"
        let bindings: [String: ResponsesToolNamespaces.Binding] = [
            wireName: .init(namespace: "workspace", name: "run")
        ]
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: chatJSONData([
                "model": "route", "input": "Use the selected namespace child",
                "tools": [["type": "function", "name": wireName]],
            ]),
            targetModel: "upstream",
            inheritedToolBindings: bindings,
            inheritedDeclaredToolBindings: bindings,
            inheritedToolNameCatalog: .init(declared: ["run"], historical: ["retired_run"]))
        #expect(prepared.toolNameCatalog == .init(declared: [wireName, "run"], historical: ["retired_run"]))
        let upstream = try chatJSONObject(prepared.upstreamBody)
        let tools = try #require(upstream["tools"] as? [[String: Any]])
        #expect(tools as NSArray == [["type": "function", "function": ["name": wireName]]] as NSArray)
        let response = try chatJSONData([
            "choices": [
                [
                    "finish_reason": "tool_calls",
                    "message": [
                        "tool_calls": [
                            ["id": "call", "type": "function", "function": ["name": name, "arguments": "{}"]]
                        ]
                    ],
                ]
            ]
        ])
        let contract = try ProviderToolContract(
            wire: .chatCompletions,
            requestBody: prepared.upstreamBody,
            declaredToolBindings: prepared.declaredToolBindings,
            toolNameCatalog: prepared.toolNameCatalog)
        #expect(throws: ProviderToolContract.Error.undeclaredTool) { try contract.validateBuffered(response) }
        let projected = try OpenAIResponsesChatCompletions.project(responseBody: response, prepared: prepared)
        let output = try #require(chatJSONObject(projected)["output"] as? [[String: Any]])
        #expect(output.first?["name"] as? String == name)
        #expect(output.first?["namespace"] == nil)
    }
}
