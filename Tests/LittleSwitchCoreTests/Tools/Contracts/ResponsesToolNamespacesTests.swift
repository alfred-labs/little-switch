import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses tool namespaces")
struct ResponsesToolNamespacesTests {
    private func namespaceTool(
        _ name: String,
        _ subTools: [String]
    ) -> [String: Any] {
        [
            "type": "namespace",
            "name": name,
            "description": "A namespace.",
            "tools": subTools.map { sub in
                [
                    "type": "function",
                    "name": sub,
                    "description": "Does \(sub).",
                    "parameters": ["type": "object", "properties": [:]],
                ] as [String: Any]
            },
        ]
    }

    @Test("A namespaced tool becomes a flat function the provider can call")
    func flattensNamespacedTools() {
        let result = ResponsesToolNamespaces.flatten(
            tools: [namespaceTool("multi_agent_v1", ["spawn_agent", "wait_agent"])]
        )

        #expect(result.tools.count == 2)
        #expect(result.tools.allSatisfy { $0["type"] as? String == "function" })
        #expect(
            result.tools.compactMap { $0["name"] as? String }
                == ["multi_agent_v1__spawn_agent", "multi_agent_v1__wait_agent"]
        )
        #expect(
            result.bindings["multi_agent_v1__spawn_agent"]
                == ResponsesToolNamespaces.Binding(
                    namespace: "multi_agent_v1",
                    name: "spawn_agent"
                )
        )
    }

    @Test("The flattened description carries the exact wire name and namespace context")
    func prefixesSubToolDescription() {
        let result = ResponsesToolNamespaces.flatten(
            tools: [namespaceTool("ns", ["do_it"])]
        )

        let tool = result.tools.first
        #expect(
            tool?["description"] as? String
                == "Call this tool by its exact name \"ns__do_it\". [ns] A namespace. Does do_it."
        )
        #expect(tool?["parameters"] != nil)
    }

    @Test("The declared bindings contain only current-turn children")
    func declaredBindingsExcludeHistory() {
        let history: [[String: Any]] = [
            [
                "type": "function_call",
                "name": "retired",
                "namespace": "gone",
                "call_id": "call_retired",
                "arguments": "{}",
            ]
        ]

        let result = ResponsesToolNamespaces.flatten(
            tools: [namespaceTool("ns", ["do_it"])],
            history: history
        )

        #expect(result.bindings["gone__retired"] != nil)
        #expect(result.declaredBindings["gone__retired"] == nil)
        #expect(
            result.declaredBindings["ns__do_it"]
                == ResponsesToolNamespaces.Binding(namespace: "ns", name: "do_it")
        )
        #expect(result.declaredBindings.count == 1)
    }

    @Test("Plain function tools pass through untouched and bind nothing")
    func leavesPlainToolsAlone() {
        let plain: [String: Any] = ["type": "function", "name": "shell"]

        let result = ResponsesToolNamespaces.flatten(tools: [plain])

        #expect(result.tools.count == 1)
        #expect(result.tools.first?["name"] as? String == "shell")
        #expect(result.bindings.isEmpty)
    }

    @Test("Non-function entries inside a namespace are dropped")
    func dropsUnsupportedSubTools() {
        let namespace: [String: Any] = [
            "type": "namespace",
            "name": "ns",
            "tools": [
                ["type": "function", "name": "ok"],
                ["type": "web_search"],
                "not-an-object",
            ],
        ]

        let result = ResponsesToolNamespaces.flatten(tools: [namespace])

        #expect(result.tools.compactMap { $0["name"] as? String } == ["ns__ok"])
    }

    @Test("A malformed namespace spec is dropped rather than half-flattened")
    func dropsMalformedNamespaces() {
        let noName: [String: Any] = [
            "type": "namespace",
            "tools": [["type": "function", "name": "orphan"]],
        ]
        let emptyName: [String: Any] = [
            "type": "namespace",
            "name": "",
            "tools": [["type": "function", "name": "orphan"]],
        ]
        let noTools: [String: Any] = ["type": "namespace", "name": "ns"]
        let unnamedSubTool: [String: Any] = [
            "type": "namespace",
            "name": "ns",
            "tools": [["type": "function"]],
        ]

        let result = ResponsesToolNamespaces.flatten(
            tools: [noName, emptyName, noTools, unnamedSubTool]
        )

        #expect(result.tools.isEmpty)
        #expect(result.bindings.isEmpty)
    }

    @Test("A collision disambiguates instead of hiding the sub-tool")
    func disambiguatesOnCollision() throws {
        let flat: [String: Any] = ["type": "function", "name": "ns__ok"]

        let result = ResponsesToolNamespaces.flatten(
            tools: [flat, namespaceTool("ns", ["ok"])]
        )

        let names = result.tools.compactMap { $0["name"] as? String }
        #expect(names.count == 2)
        #expect(names.first == "ns__ok")
        let disambiguated = names.last ?? ""
        #expect(disambiguated != "ns__ok")
        #expect(disambiguated.count <= ResponsesToolNamespaces.maximumNameLength)
        #expect(result.bindings[disambiguated] != nil)

        // History replay maps the restored pair to the disambiguated wire name.
        let replay = ResponsesToolNamespaces.replayName(
            bindings: result.bindings,
            namespace: "ns",
            name: "ok"
        )
        #expect(replay == disambiguated)
        #expect(
            ResponsesToolNamespaces.replayName(
                bindings: result.bindings,
                namespace: "unknown",
                name: "tool"
            ) == "unknown__tool"
        )

        // A second collision with the first fingerprint itself re-salts.
        let firstFingerprint: [String: Any] = ["type": "function", "name": disambiguated]
        let resalted = ResponsesToolNamespaces.flatten(
            tools: [flat, firstFingerprint, namespaceTool("ns", ["ok"])]
        )
        let resaltedNames = resalted.tools.compactMap { $0["name"] as? String }
        #expect(resaltedNames.count == 3)
        #expect(resaltedNames.contains("ns__ok"))
        #expect(resaltedNames.contains(disambiguated))
        let resaltedBinding = try #require(
            resalted.bindings.first { _, value in
                value == ResponsesToolNamespaces.Binding(namespace: "ns", name: "ok")
            }?.key
        )
        #expect(resaltedBinding != disambiguated)
        #expect(resaltedBinding != "ns__ok")
    }

    @Test("An over-long flat name falls back to a stable opaque name")
    func shortensOverLongNames() {
        let long = String(repeating: "a", count: 40)
        let result = ResponsesToolNamespaces.flatten(
            tools: [namespaceTool(long, [String(repeating: "b", count: 40)])]
        )

        let name = result.tools.first?["name"] as? String
        #expect((name?.count ?? .max) <= ResponsesToolNamespaces.maximumNameLength)
        #expect(result.bindings[name ?? ""]?.namespace == long)

        let again = ResponsesToolNamespaces.flatten(
            tools: [namespaceTool(long, [String(repeating: "b", count: 40)])]
        )
        #expect(again.tools.first?["name"] as? String == name)
    }

    @Test("Replayed history uses the same flat name as the tool declaration")
    func historyNameMatchesDeclaration() {
        let result = ResponsesToolNamespaces.flatten(
            tools: [namespaceTool("multi_agent_v1", ["spawn_agent"])]
        )

        #expect(
            ResponsesToolNamespaces.flattenedName(
                namespace: "multi_agent_v1",
                name: "spawn_agent"
            ) == result.tools.first?["name"] as? String
        )
    }
}
