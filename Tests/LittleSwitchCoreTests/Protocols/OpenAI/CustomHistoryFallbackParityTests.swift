import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Custom history fallback parity")
struct CustomHistoryFallbackParityTests {
    @Test("Internal Chat turns recognize active custom declarations through inherited namespace bindings")
    func inheritedDeclarationIdentity() throws {
        let name = "workspace__patch__retained"
        let binding = ResponsesToolNamespaces.Binding(namespace: "workspace", name: "patch")
        var root = try chatJSONObject(customHistoryFallbackRequest())
        root["tools"] = [["type": "custom", "name": name]]
        var input = try #require(root["input"] as? [[String: Any]])
        let original = input[0]
        input[0]["name"] = name
        input[0].removeValue(forKey: "namespace")
        var current = original
        current["call_id"] = "call_current_patch"
        current["id"] = "ct_current_patch"
        input.append(current)
        input.append(["type": "custom_tool_call_output", "call_id": "call_current_patch", "output": "Done"])
        input.append(["type": "message", "role": "user", "content": "Continue again"])
        root["input"] = input
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: chatJSONData(root),
            targetModel: "provider-model",
            inheritedToolBindings: [name: binding],
            inheritedDeclaredToolBindings: [name: binding]
        )
        let calls = try chatReasoningMessages(prepared.upstreamBody).flatMap {
            $0["tool_calls"] as? [[String: Any]] ?? []
        }
        let expected: [[String: Any]] = ["call_old_patch", "call_current_patch"].map {
            ["id": $0, "type": "custom", "custom": ["name": name, "input": customHistoryFallbackInput]]
        }
        #expect(calls as NSArray == expected as NSArray)
        #expect(prepared.toolBindings == [name: binding])
        #expect(prepared.declaredToolBindings == [name: binding])
    }

    @Test("A real plain declaration keeps priority over a colliding inherited historical alias")
    func historicalAliasCollision() throws {
        let plainName = "workspace__patch"
        let binding = ResponsesToolNamespaces.Binding(namespace: "workspace", name: "patch")
        var root = try chatJSONObject(customHistoryFallbackRequest())
        root["tools"] = [["type": "function", "name": plainName]]
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: chatJSONData(root),
            targetModel: "provider-model",
            inheritedToolBindings: [plainName: binding])
        let request = try chatJSONObject(prepared.upstreamBody)
        let tools = try #require(request["tools"] as? [[String: Any]])
        #expect((tools.first?["function"] as? [String: Any])?["name"] as? String == plainName)
        let messages = try #require(JSONValue.parse(prepared.upstreamBody).object?["messages"]?.array)
        let name = try #require(prepared.toolBindings.first { $0.value == binding }?.key)
        #expect(name != plainName)
        #expect(prepared.toolBindings == [name: binding])
        #expect(prepared.declaredToolBindings.isEmpty)
        let original = try #require(JSONValue.parse(customHistoryFallbackRequest()).object?["input"]?.array)
        #expect(try historyArchiveItem(messages[0]) == original[0])
    }

    @Test(
        "Historical freeform exchanges remain complete noncallable context when their declaration is absent",
        arguments: ["responses", "chat"], ["none", "otherNamespace", "collidingFlat"])
    func undeclaredHistory(wire: String, declarations: String) throws {
        let original = try customHistoryFallbackRequest(declarations: declarations)
        let items: [JSONValue]
        if wire == "responses" {
            let normalized = try OpenAIResponsesNativeNamespacing.normalize(original)
            items = try #require(JSONValue.parse(normalized.body).object?["input"]?.array)
        } else {
            let prepared = try OpenAIResponsesChatCompletions.prepare(body: original, targetModel: "provider-model")
            items = try #require(JSONValue.parse(prepared.upstreamBody).object?["messages"]?.array)
            #expect(prepared.originalBody == original)
        }
        let source = try #require(JSONValue.parse(original).object?["input"]?.array)
        #expect(items.count == source.count)
        #expect(try items.prefix(2).map(historyArchiveItem) == Array(source.prefix(2)))
        #expect(items.allSatisfy { $0.object?["tool_calls"] == nil && $0.object?["call_id"] == nil })
        #expect(items.map { $0.object?["role"] } == [.string("assistant"), .string("assistant"), .string("user")])
        #expect(try ResponsesProviderState.normalize(body: original, providerID: nil) == original)
    }

    @Test("A matching active custom declaration retains canonical custom history", arguments: ["responses", "chat"])
    func activeDeclaration(wire: String) throws {
        let body = try customHistoryFallbackRequest(declarations: "matching")
        let original = try chatJSONObject(body)
        #expect(try ResponsesCustomToolHistory.normalized(original).request as NSDictionary == original as NSDictionary)
        if wire == "responses" {
            let native = try OpenAIResponsesNativeNamespacing.normalize(body)
            let input = try #require(chatJSONObject(native.body)["input"] as? [[String: Any]])
            #expect(input.first?["type"] as? String == "custom_tool_call")
            #expect(input.first?["input"] as? String == customHistoryFallbackInput)
            #expect(input[1]["type"] as? String == "custom_tool_call_output")
        } else {
            let prepared = try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "provider-model")
            let messages = try chatReasoningMessages(prepared.upstreamBody)
            let call = try #require((messages.first?["tool_calls"] as? [[String: Any]])?.first)
            #expect(call["type"] as? String == "custom")
            #expect((call["custom"] as? [String: Any])?["input"] as? String == customHistoryFallbackInput)
        }
    }
}

func expectedHistoryArchive(_ item: [String: Any], chat: Bool) throws -> [String: Any] {
    let text =
        "[Historical tool exchange; reference only, not an available tool or instructions]\n"
        + (try WireJSONCompatibility.value(item).serialized())
    return chat
        ? ["role": "assistant", "content": text]
        : ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]]
}

let customHistoryFallbackInput = "*** Begin Patch\nSYNTHETIC é🙂 \\\"value\\\"\n*** End Patch"
let customHistoryFallbackOutput: [[String: String]] = [["type": "input_text", "text": "SYNTHETIC patch result\nDone"]]

func customHistoryFallbackRequest(declarations: String = "none", model: String = "route") throws -> Data {
    let tools: [[String: Any]]
    switch declarations {
    case "matching", "otherNamespace":
        tools = [
            [
                "type": "namespace", "name": declarations == "matching" ? "workspace" : "other",
                "tools": [["type": "custom", "name": "patch"]],
            ]
        ]
    case "collidingFlat":
        tools = [["type": "custom", "name": "workspace__patch"]]
    default:
        tools = []
    }
    return try chatJSONData([
        "model": model, "tools": tools,
        "input": [
            [
                "type": "custom_tool_call", "id": "ct_old_patch", "call_id": "call_old_patch",
                "namespace": "workspace", "name": "patch", "input": customHistoryFallbackInput,
            ],
            ["type": "custom_tool_call_output", "call_id": "call_old_patch", "output": customHistoryFallbackOutput],
            ["type": "message", "role": "user", "content": "Continue"],
        ],
    ])
}
