import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Provider tool identities are exact UTF-8")
struct ProviderToolByteIdentityTests {
    private let composed = "é"
    private let decomposed = "e\u{301}"

    @Test("Unicode namespace segments do not merge qualified aliases")
    func namespaceSegments() throws {
        let flattened = ResponsesToolNamespaces.flatten(tools: [
            ["type": "namespace", "name": composed, "tools": [["type": "function", "name": "read"]]],
            ["type": "namespace", "name": decomposed, "tools": [["type": "function", "name": "write"]]],
        ])
        let resolver = ProviderToolNamespaceResolver(declaredBindings: flattened.declaredBindings)
        #expect(resolver.wireName(for: "functions.\(composed).write", namespace: nil) == nil)
        #expect(resolver.wireName(for: "functions.\(decomposed).read", namespace: nil) == nil)
        #expect(resolver.wireName(for: "functions.\(composed).read", namespace: nil) == composed + "__read")
        #expect(resolver.wireName(for: "functions.\(decomposed).write", namespace: nil) == decomposed + "__write")
    }

    @Test("Canonical Unicode equivalence never authorizes a different wire name", arguments: [false, true])
    func emittedName(namespaced: Bool) throws {
        let tools: [[String: Any]] =
            namespaced
            ? [["type": "namespace", "name": "workspace", "tools": [["type": "function", "name": composed]]]]
            : [["type": "function", "name": composed]]
        let body = try chatJSONData(["model": "route", "input": "go", "tools": tools])
        let prepared = try OpenAIResponsesNativeNamespacing.normalize(body)
        let contract = try ProviderToolContract(
            wire: .responses,
            requestBody: prepared.body,
            declaredToolBindings: prepared.declaredToolBindings,
            toolNameCatalog: prepared.toolNameCatalog)
        let names =
            namespaced ? [decomposed, "workspace__" + decomposed, "functions.workspace." + decomposed] : [decomposed]
        for name in names {
            #expect(throws: ProviderToolContract.Error.undeclaredTool(name: name)) {
                try contract.validateBuffered(
                    chatJSONData([
                        "output": [["type": "function_call", "call_id": "new", "name": name, "arguments": "{}"]]
                    ]))
            }
        }
    }

    @Test("A retired canonically equivalent custom identity remains retired", arguments: [false, true], [false, true])
    func historicalIdentity(chat: Bool, namespaceDifference: Bool) throws {
        let currentNamespace = namespaceDifference ? composed : "workspace"
        let retiredNamespace = namespaceDifference ? decomposed : "workspace"
        let currentName = namespaceDifference ? "exec" : composed
        let retiredName = namespaceDifference ? "exec" : decomposed
        let body = try chatJSONData([
            "model": "route",
            "tools": [
                ["type": "namespace", "name": currentNamespace, "tools": [["type": "custom", "name": currentName]]]
            ],
            "input": [
                [
                    "type": "custom_tool_call", "call_id": "old", "namespace": retiredNamespace, "name": retiredName,
                    "input": "old",
                ],
                ["type": "custom_tool_call_output", "call_id": "old", "output": "result"],
            ],
        ])
        let data =
            chat
            ? try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "provider").upstreamBody
            : try OpenAIResponsesNativeNamespacing.normalize(body).body
        let items = try #require(JSONValue.parse(data).object?[chat ? "messages" : "input"]?.array)
        let original = try historyArchiveItem(items[0])
        #expect(Data(try #require(original.object?["name"]?.string).utf8) == Data(retiredName.utf8))
        #expect(Data(try #require(original.object?["namespace"]?.string).utf8) == Data(retiredNamespace.utf8))
    }

    @Test("An allowed selection must use the declared UTF-8 identity")
    func selectionIdentity() throws {
        let body = try chatJSONData([
            "tools": [["type": "custom", "name": composed]],
            "tool_choice": [
                "type": "allowed_tools", "mode": "auto", "tools": [["type": "custom", "name": decomposed]],
            ],
        ])
        #expect(throws: ProviderToolContract.Error.invalidRequest) {
            _ = try CustomToolProjection.prepare(body: body, wire: .responses, adapt: true)
        }
    }
}
