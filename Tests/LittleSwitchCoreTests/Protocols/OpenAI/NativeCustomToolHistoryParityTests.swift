import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Native custom tool history parity")
struct NativeCustomToolHistoryParityTests {
    @Test(
        "Native custom image exchanges preserve their history and receive an explicit budget", arguments: [false, true])
    func plainCustomHistory(declaredBudget: Bool) throws {
        var request: [String: Any] = [
            "model": "client", "input": history,
            "tools": [["type": "custom", "name": "patch"]],
        ]
        if declaredBudget { request["max_output_tokens"] = 512 }
        let body = try chatJSONData(request)
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(body)
        let expected: [String: Any] = [
            "model": "client", "input": history,
            "tools": [["type": "custom", "name": "patch"]],
            "max_output_tokens": declaredBudget ? 512 : 32_768,
        ]
        #expect(try chatJSONObject(normalized.body) as NSDictionary == expected as NSDictionary)
        if declaredBudget { #expect(normalized.body == body) }
    }

    @Test("Namespaced custom history uses a collision-safe current binding while preserving the result payload")
    func namespacedCustomHistory() throws {
        var call = history[0]
        call["namespace"] = "workspace"
        let body = try chatJSONData([
            "model": "client", "input": [call, history[1]],
            "tools": [
                ["type": "custom", "name": "workspace__patch"],
                ["type": "namespace", "name": "workspace", "tools": [["type": "custom", "name": "patch"]]],
            ],
            "tool_choice": ["type": "custom", "namespace": "workspace", "name": "patch"],
        ])
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(body)
        let binding = ResponsesToolNamespaces.Binding(namespace: "workspace", name: "patch")
        let name = try #require(normalized.toolBindings.first { $0.value == binding }?.key)
        #expect(name != "workspace__patch")
        #expect(normalized.declaredToolBindings[name] == binding)
        let upstream = try chatJSONObject(normalized.body)
        let input = try #require(upstream["input"] as? [[String: Any]])
        var expectedCall = call
        expectedCall["name"] = name
        expectedCall.removeValue(forKey: "namespace")
        #expect(input as NSArray == [expectedCall, history[1]] as NSArray)
        #expect(upstream["tool_choice"] as? NSDictionary == ["type": "custom", "name": name] as NSDictionary)
        #expect((upstream["tools"] as? [[String: Any]])?.count == 2)
    }

    @Test("Retired custom history keeps its namespace identity without authorizing a new emission")
    func retiredCustomHistory() throws {
        var call = history[0]
        call["namespace"] = "retired"
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(
            chatJSONData([
                "model": "client", "input": [call, history[1]],
                "tools": [["type": "custom", "name": "retired__patch"]],
            ]))
        let name = try #require(
            normalized.toolBindings.first { $0.value == .init(namespace: "retired", name: "patch") }?.key)
        #expect(name != "retired__patch")
        #expect(normalized.declaredToolBindings.isEmpty)
        let input = try #require(chatJSONObject(normalized.body)["input"] as? [[String: Any]])
        var expectedCall = call
        expectedCall["name"] = name
        expectedCall["type"] = "function_call"
        expectedCall["arguments"] = try chatReasoningText(
            chatJSONData(["input": try #require(call["input"] as? String)]))
        expectedCall.removeValue(forKey: "namespace")
        expectedCall.removeValue(forKey: "input")
        var expectedOutput = history[1]
        expectedOutput["type"] = "function_call_output"
        #expect(input as NSArray == [expectedCall, expectedOutput] as NSArray)
        let contract = try ProviderToolContract(wire: .responses, requestBody: normalized.body)
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: name)) {
            try contract.validateBuffered(
                chatJSONData(["output": [["type": "function_call", "name": name, "arguments": #"{"input":"new"}"#]]]))
        }
    }

    private var history: [[String: Any]] {
        [
            [
                "type": "custom_tool_call", "id": "ct_old", "call_id": "call_patch", "name": "patch",
                "input": "raw patch\né🙂",
            ],
            [
                "type": "custom_tool_call_output", "call_id": "call_patch",
                "output": [
                    ["type": "input_text", "text": "Applied."],
                    ["type": "input_image", "image_url": "data:image/png;base64,AA=="],
                ],
            ],
        ]
    }
}
