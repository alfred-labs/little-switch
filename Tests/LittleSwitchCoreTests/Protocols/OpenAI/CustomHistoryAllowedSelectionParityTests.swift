import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Custom history allowed selection parity")
struct CustomHistoryAllowedSelectionParityTests {
    struct Selection: Sendable {
        let mode: String
        let subset: String

        static let cases = ["auto", "required"].flatMap { mode in
            ["excluded", "included", "empty"].map { Selection(mode: mode, subset: $0) }
        }
    }

    @Test(
        "Only custom declarations in the outgoing allowed subset keep custom history active",
        arguments: ["responses", "chat"], Selection.cases)
    func selectedCustomHistory(wire: String, selection: Selection) throws {
        let original = try request(selection: selection)
        if selection.mode == "required", selection.subset == "empty" {
            if wire == "chat" {
                #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                    _ = try OpenAIResponsesChatCompletions.prepare(body: original, targetModel: "upstream")
                }
            } else {
                #expect(throws: ProviderToolContract.Error.invalidRequest) {
                    _ = try OpenAIResponsesNativeNamespacing.normalize(original)
                }
            }
            return
        }

        let upstream: [String: Any]
        let bindings: [String: ResponsesToolNamespaces.Binding]
        let declaredNames: Set<String>
        let historicalNames: Set<String>
        if wire == "chat" {
            let prepared = try OpenAIResponsesChatCompletions.prepare(body: original, targetModel: "upstream")
            upstream = try chatJSONObject(prepared.upstreamBody)
            bindings = prepared.toolBindings
            declaredNames = prepared.toolNameCatalog.declared
            historicalNames = prepared.toolNameCatalog.historical
            #expect(prepared.originalBody == original)
        } else {
            let prepared = try OpenAIResponsesNativeNamespacing.normalize(original)
            upstream = try chatJSONObject(prepared.body)
            bindings = prepared.toolBindings
            declaredNames = prepared.toolNameCatalog.declared
            historicalNames = prepared.toolNameCatalog.historical
        }
        let name = ResponsesToolNamespaces.replayName(bindings: bindings, namespace: "workspace", name: "patch")
        #expect(declaredNames == ["selected", name])
        #expect(historicalNames == [name])
        #expect(
            upstream as NSDictionary == (try expected(wire: wire, selection: selection, name: name)) as NSDictionary)
        #expect(try ResponsesProviderState.normalize(body: original, providerID: nil) == original)
    }

    private func request(selection: Selection) throws -> Data {
        var root = try chatJSONObject(customHistoryFallbackRequest(declarations: "matching"))
        var tools = try #require(root["tools"] as? [[String: Any]])
        tools.insert(["type": "function", "name": "selected"], at: 0)
        root["tools"] = tools
        var references: [[String: Any]] =
            selection.subset == "empty" ? [] : [["type": "function", "name": "selected"]]
        if selection.subset == "included" {
            references.append(["type": "custom", "namespace": "workspace", "name": "patch"])
        }
        root["tool_choice"] = ["type": "allowed_tools", "mode": selection.mode, "tools": references]
        return try chatJSONData(root)
    }

    private func expected(wire: String, selection: Selection, name: String) throws -> [String: Any] {
        let custom = selection.subset == "included"
        let kind = custom ? "custom" : "function"
        let key = custom ? "input" : "arguments"
        let payload =
            custom
            ? customHistoryFallbackInput : try chatReasoningText(chatJSONData(["input": customHistoryFallbackInput]))
        var result: [String: Any] = [
            "model": wire == "chat" ? "upstream" : "route",
            "tool_choice": selection.subset == "empty" ? "none" : selection.mode,
        ]
        if wire == "chat" {
            let call: [String: Any] = ["id": "call_old_patch", "type": kind, kind: ["name": name, key: payload]]
            result["messages"] = [
                ["role": "assistant", "content": NSNull(), "tool_calls": [call]],
                [
                    "role": "tool", "tool_call_id": "call_old_patch",
                    "content": try chatReasoningText(chatJSONData(customHistoryFallbackOutput)),
                ],
                ["role": "user", "content": "Continue"],
            ]
            result["stream"] = false
        } else {
            let responseType = custom ? "custom_tool_call" : "function_call"
            result["input"] = [
                [
                    "type": responseType, "id": "ct_old_patch", "call_id": "call_old_patch", "name": name,
                    key: payload,
                ],
                ["type": "\(responseType)_output", "call_id": "call_old_patch", "output": customHistoryFallbackOutput],
                ["type": "message", "role": "user", "content": "Continue"],
            ]
        }
        if selection.subset != "empty" {
            var tools: [[String: Any]] = [
                wire == "chat"
                    ? ["type": "function", "function": ["name": "selected"]]
                    : ["type": "function", "name": "selected"]
            ]
            if custom {
                let description = "Call this tool by its exact name \"\(name)\". [workspace]"
                tools.append(
                    wire == "chat"
                        ? ["type": "custom", "custom": ["name": name, "description": description]]
                        : ["type": "custom", "name": name, "description": description])
            }
            result["tools"] = tools
        }
        return result
    }
}
