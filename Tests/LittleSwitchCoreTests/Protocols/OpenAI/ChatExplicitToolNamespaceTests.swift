import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Chat explicit tool namespace parity")
struct ChatExplicitToolNamespaceTests {
    @Test("An explicit namespace overrides the identically named plain declaration in Chat JSON")
    func bufferedExplicitPair() throws {
        let prepared = try preparedRequest()
        let response = try chatJSONData([
            "choices": [["finish_reason": "tool_calls", "message": ["tool_calls": [call(namespace: "workspace")]]]]
        ])
        let projected = try OpenAIResponsesChatCompletions.project(responseBody: response, prepared: prepared)
        let output = try #require(chatJSONObject(projected)["output"] as? [[String: Any]])
        #expect(output.count == 1)
        #expect(output.first?["name"] as? String == "run")
        #expect(output.first?["namespace"] as? String == "workspace")
    }

    @Test("Chat live and completed items retain the explicit namespace pair")
    func streamingExplicitPair() throws {
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: try preparedRequest())
        var events = try accumulator.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: ["tool_calls": [call(namespace: "workspace")]])
            ]))
        events += try accumulator.consume(
            chatChunkFrame(
                choices: [chatChoice(delta: [:], finishReason: "tool_calls")],
                usage: ["prompt_tokens": 0, "completion_tokens": 0]))
        events += try accumulator.consume(chatDoneFrame())
        let items = try events.compactMap { event -> [String: Any]? in
            switch event {
            case .outputItemAdded(_, let data), .outputItemDone(_, let data):
                try chatJSONObject(data)
            default:
                nil
            }
        }
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0["name"] as? String == "run" && $0["namespace"] as? String == "workspace" })
        let output = try #require(chatJSONObject(accumulator.finish().rootJSON)["output"] as? [[String: Any]])
        #expect(output.first?["namespace"] as? String == "workspace")
    }

    @Test(
        "Chat JSON rejects undeclared and malformed explicit namespaces",
        arguments: ["\"unknown\"", "7", "\"\""])
    func bufferedRejectsInvalidNamespace(namespaceJSON: String) throws {
        let namespace = try JSONSerialization.jsonObject(with: Data(namespaceJSON.utf8), options: .fragmentsAllowed)
        let prepared = try preparedRequest()
        let contract = try ProviderToolContract(
            wire: .chatCompletions,
            requestBody: prepared.upstreamBody,
            declaredToolBindings: prepared.declaredToolBindings)
        let body = try chatJSONData([
            "choices": [["finish_reason": "tool_calls", "message": ["tool_calls": [call(namespace: namespace)]]]]
        ])
        #expect(throws: (any Error).self) { try contract.validateBuffered(body) }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            try OpenAIResponsesChatCompletions.project(responseBody: body, prepared: prepared)
        }
    }

    @Test("Chat stream validation rejects an explicit undeclared namespace before success")
    func streamingRejectsUnknownNamespace() throws {
        let prepared = try preparedRequest()
        var contract = try ProviderToolContract(
            wire: .chatCompletions,
            requestBody: prepared.upstreamBody,
            declaredToolBindings: prepared.declaredToolBindings)
        #expect(throws: ProviderToolContract.Error.undeclaredTool) {
            try contract.validateFrame(
                chatChunkFrame(choices: [
                    chatChoice(delta: ["tool_calls": [call(namespace: "unknown")]], finishReason: "tool_calls")
                ]))
        }
    }

    @Test("Chat namespace identity cannot change during argument continuations")
    func streamingRejectsChangedNamespace() throws {
        let prepared = try preparedRequest()
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try accumulator.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: ["tool_calls": [call(namespace: "workspace")]])
            ]))
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            try accumulator.consume(
                chatChunkFrame(choices: [
                    chatChoice(delta: ["tool_calls": [call(namespace: "other")]])
                ]))
        }
        var contract = try ProviderToolContract(
            wire: .chatCompletions,
            requestBody: prepared.upstreamBody,
            declaredToolBindings: prepared.declaredToolBindings)
        try contract.validateFrame(
            chatChunkFrame(choices: [
                chatChoice(delta: ["tool_calls": [call(namespace: "workspace")]])
            ]))
        #expect(throws: ProviderToolContract.Error.invalidResponse) {
            try contract.validateFrame(
                chatChunkFrame(choices: [
                    chatChoice(delta: ["tool_calls": [call(namespace: "other")]])
                ]))
        }
    }

    private func preparedRequest() throws -> PreparedResponsesChatCompletionsRequest {
        let function: [String: Any] = ["type": "function", "name": "run", "parameters": ["type": "object"]]
        return try OpenAIResponsesChatCompletions.prepare(
            body: chatJSONData([
                "model": "client", "input": "Run the task.",
                "tools": [function, ["type": "namespace", "name": "workspace", "tools": [function]]],
            ]),
            targetModel: "upstream",
            mode: .streaming(toolStream: true))
    }

    private func call(namespace: Any) -> [String: Any] {
        [
            "index": 0, "id": "call_run", "type": "function",
            "function": ["name": "run", "namespace": namespace, "arguments": "{}"],
        ]
    }
}
