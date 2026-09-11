import Foundation
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
        let messages = try chatReasoningMessages(prepared.upstreamBody)
        let call = try #require((messages.first?["tool_calls"] as? [[String: Any]])?.first)
        let name = try #require((call["function"] as? [String: Any])?["name"] as? String)
        #expect(name != plainName)
        #expect(prepared.toolBindings == [name: binding])
        #expect(prepared.declaredToolBindings.isEmpty)
    }

    @Test(
        "Historical freeform calls use function history when their declaration is absent",
        arguments: ["responses", "chat"], ["none", "otherNamespace", "collidingFlat"])
    func undeclaredHistory(wire: String, declarations: String) throws {
        let original = try customHistoryFallbackRequest(declarations: declarations)
        let call: [String: Any]
        let output: [String: Any]
        let name: String
        if wire == "responses" {
            let normalized = try OpenAIResponsesNativeNamespacing.normalize(original)
            let input = try #require(chatJSONObject(normalized.body)["input"] as? [[String: Any]])
            call = try #require(input.first)
            output = input[1]
            name = ResponsesToolNamespaces.replayName(
                bindings: normalized.toolBindings, namespace: "workspace", name: "patch")
            #expect(call["type"] as? String == "function_call")
            #expect(call["name"] as? String == name)
            #expect(call["namespace"] == nil)
            #expect(call["call_id"] as? String == "call_old_patch")
            #expect(output["type"] as? String == "function_call_output")
            #expect(output["call_id"] as? String == "call_old_patch")
            #expect(try chatJSONData(#require(output["output"])) == chatJSONData(customHistoryFallbackOutput))
        } else {
            let prepared = try OpenAIResponsesChatCompletions.prepare(body: original, targetModel: "provider-model")
            let messages = try chatReasoningMessages(prepared.upstreamBody)
            call = try #require((messages.first?["tool_calls"] as? [[String: Any]])?.first)
            output = messages[1]
            name = ResponsesToolNamespaces.replayName(
                bindings: prepared.toolBindings, namespace: "workspace", name: "patch")
            #expect(call["type"] as? String == "function")
            #expect((call["function"] as? [String: Any])?["name"] as? String == name)
            #expect(call["id"] as? String == "call_old_patch")
            #expect(output["role"] as? String == "tool")
            #expect(output["tool_call_id"] as? String == "call_old_patch")
            #expect(output["content"] as? String == (try chatReasoningText(chatJSONData(customHistoryFallbackOutput))))
        }
        let function = wire == "responses" ? call : try #require(call["function"] as? [String: Any])
        let arguments = try #require(function["arguments"] as? String)
        #expect(
            try chatJSONObject(Data(arguments.utf8)) as NSDictionary == ["input": customHistoryFallbackInput]
                as NSDictionary)
        #expect(try ResponsesProviderState.normalize(body: original, providerID: nil) == original)
    }

    @Test("A matching active custom declaration retains canonical custom history", arguments: ["responses", "chat"])
    func activeDeclaration(wire: String) throws {
        let body = try customHistoryFallbackRequest(declarations: "matching")
        let original = try chatJSONObject(body)
        #expect(try ResponsesCustomToolHistory.normalized(original) as NSDictionary == original as NSDictionary)
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
