import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Provider namespace identity contract")
struct NamespaceIdentityContractTests {
    @Test(
        "Ambiguous bare children never authorize a shorter tool",
        arguments: [ProviderToolContract.Wire.responses, .chatCompletions])
    func ambiguousChildCannotAuthorizeSuffix(wire: ProviderToolContract.Wire) throws {
        let bindings: [String: ResponsesToolNamespaces.Binding] = [
            "x__a_b": .init(namespace: "x", name: "a_b"),
            "y__a_b": .init(namespace: "y", name: "a_b"),
            "z__b": .init(namespace: "z", name: "b"),
        ]
        let functions = bindings.keys.sorted().map { ["type": "function", "name": $0] }
        let tools: [[String: Any]] =
            wire == .chatCompletions ? functions.map { ["type": "function", "function": $0] } : functions
        let contract = try ProviderToolContract(
            wire: wire,
            requestBody: chatJSONData(["tools": tools]),
            declaredToolBindings: bindings)
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "a_b")) {
            try contract.validateBuffered(response(wire: wire, name: "a_b"))
        }
        for name in bindings.keys { try contract.validateBuffered(response(wire: wire, name: name)) }
    }

    @Test(
        "Plain declarations prevent ambiguous namespace recovery",
        arguments: [
            ProviderToolContract.Wire.responses, .chatCompletions,
        ])
    func plainDeclarationVetoesNearMiss(wire: ProviderToolContract.Wire) throws {
        let contract = try ProviderToolContract(
            wire: wire,
            requestBody: request(wire: wire, plain: ["spawn_agent"]),
            declaredToolBindings: bindings
        )
        for name in ["spawn_agent", "collaboration__spawn_agent"] {
            try contract.validateBuffered(response(wire: wire, name: name))
        }
        for name in ["functions.collaboration.spawn_agent", "mcp__tools__collaboration_spawn_agent"] {
            #expect(throws: ProviderToolContract.Error.undeclaredTool(name: name)) {
                try contract.validateBuffered(response(wire: wire, name: name))
            }
        }
    }

    @Test(
        "Exact retired history names never retarget a current namespace child",
        arguments: [
            ProviderToolContract.Wire.responses, .chatCompletions,
        ])
    func retiredHistoryNeverAuthorizes(wire: ProviderToolContract.Wire) throws {
        let contract = try ProviderToolContract(
            wire: wire,
            requestBody: request(wire: wire, history: ["spawn_agent", "gone__spawn_agent"]),
            declaredToolBindings: bindings
        )
        for name in ["spawn_agent", "gone__spawn_agent"] {
            #expect(throws: ProviderToolContract.Error.undeclaredTool(name: name)) {
                try contract.validateBuffered(response(wire: wire, name: name))
            }
        }
        try contract.validateBuffered(response(wire: wire, name: "collaboration__spawn_agent"))
    }

    @Test("A retired legacy chat function call cannot authorize a new namespaced call")
    func retiredLegacyHistoryNeverAuthorizes() throws {
        var body = try chatJSONObject(request(wire: .chatCompletions))
        body["messages"] = [["role": "assistant", "function_call": ["name": "gone__spawn_agent", "arguments": "{}"]]]
        let contract = try ProviderToolContract(
            wire: .chatCompletions, requestBody: chatJSONData(body), declaredToolBindings: bindings
        )
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "gone__spawn_agent")) {
            try contract.validateBuffered(response(wire: .chatCompletions, name: "gone__spawn_agent"))
        }
    }

    @Test("The name catalog reserves call history and excludes unrelated item names")
    func nameCatalogHistory() throws {
        let responses = try ProviderToolContractCatalog(
            wire: .responses,
            requestBody: chatJSONData([
                "tools": [["type": "function", "name": "current"]],
                "input": [
                    ["type": "function_call", "name": "retired"],
                    ["type": "custom_tool_call", "name": "retired_custom"],
                    ["type": "message", "name": "not_a_tool"],
                    ["name": "missing_type"],
                    ["type": 7, "name": "non_string_type"],
                    ["type": "function_call"],
                ],
            ]))
        #expect(
            responses.nameCatalog
                == ProviderToolNameCatalog(
                    declared: ["current"], historical: ["retired", "retired_custom"]
                ))
        let chat = try ProviderToolContractCatalog(
            wire: .chatCompletions,
            requestBody: chatJSONData([
                "messages": [
                    [
                        "tool_calls": [
                            ["type": "custom", "custom": ["name": "retired_custom"]],
                            ["type": "provider_owned", "provider_owned": ["name": "not_a_tool"]],
                            ["type": "function", "function": ["name": "retired"]],
                            ["type": "function"],
                            ["id": "not_a_call"],
                        ]
                    ]
                ]
            ]))
        #expect(chat.nameCatalog == ProviderToolNameCatalog(historical: ["retired", "retired_custom"]))
    }

    private var bindings: [String: ResponsesToolNamespaces.Binding] {
        ["collaboration__spawn_agent": .init(namespace: "collaboration", name: "spawn_agent")]
    }

    private func request(
        wire: ProviderToolContract.Wire,
        plain: [String] = [],
        history: [String] = []
    ) throws -> Data {
        let functions = (plain + ["collaboration__spawn_agent"]).map { ["type": "function", "name": $0] }
        if wire == .chatCompletions {
            return try chatJSONData([
                "tools": functions.map { ["type": "function", "function": $0] },
                "messages": history.map { name in
                    ["role": "assistant", "tool_calls": [["type": "function", "function": ["name": name]]]]
                },
            ])
        }
        return try chatJSONData([
            "tools": functions,
            "input": history.map { ["type": "function_call", "name": $0] },
        ])
    }

    private func response(wire: ProviderToolContract.Wire, name: String) throws -> Data {
        if wire == .chatCompletions {
            return try chatJSONData([
                "choices": [["message": ["tool_calls": [["type": "function", "function": ["name": name]]]]]]
            ])
        }
        return try chatJSONData(["output": [["type": "function_call", "name": name]]])
    }
}
