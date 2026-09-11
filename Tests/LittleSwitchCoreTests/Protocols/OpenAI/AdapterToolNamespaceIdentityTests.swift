import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Adapter tool namespace identity")
struct AdapterToolNamespaceIdentityTests {
    @Test("Chat JSON preserves a declared plain function beside an identically named namespace child")
    func chatBufferedPlainIdentity() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(body: requestBody(), targetModel: "upstream")
        let projected = try OpenAIResponsesChatCompletions.project(
            responseBody: chatJSONData([
                "choices": [
                    [
                        "finish_reason": "tool_calls",
                        "message": ["tool_calls": chatCalls()],
                    ]
                ]
            ]),
            prepared: prepared
        )
        let output = try #require(chatJSONObject(projected)["output"] as? [[String: Any]])
        #expect(identities(output) == expectedIdentities)
    }

    @Test("Native JSON preserves a declared plain function beside an identically named namespace child")
    func nativeBufferedPlainIdentity() throws {
        let prepared = try nativePrepared()
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(
            responseData(
                responseObject(
                    id: "resp_identity",
                    createdAt: 1,
                    status: "completed",
                    output: nativeCalls(),
                    usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
                )))
        let projected = try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: prepared, traces: [], finalTurn: turn, usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
        )
        let output = try #require(chatJSONObject(projected)["output"] as? [[String: Any]])
        #expect(identities(output) == expectedIdentities)
    }

    @Test("Chat SSE preserves a declared plain function throughout its live and completed calls")
    func chatStreamingPlainIdentity() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: requestBody(), targetModel: "upstream", mode: .streaming(toolStream: true)
        )
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        let events = try accumulator.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "tool_calls": chatCalls().enumerated().map { index, call in
                        var call = call
                        call["index"] = index
                        return call
                    }
                ])
            ]))
        #expect(try addedIdentities(events) == expectedIdentities)
        _ = try accumulator.consume(
            chatChunkFrame(
                choices: [chatChoice(delta: [:], finishReason: "tool_calls")],
                usage: ["prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0]
            ))
        _ = try accumulator.consume(chatDoneFrame())
        let output = try #require(chatJSONObject(accumulator.finish().rootJSON)["output"] as? [[String: Any]])
        #expect(identities(output) == expectedIdentities)
    }

    @Test("Native SSE preserves a declared plain function throughout its live calls")
    func nativeStreamingPlainIdentity() throws {
        let prepared = try nativePrepared()
        var accumulator = OpenAIResponsesTurnAccumulator(
            maximumTurnBytes: 64 * 1_024,
            toolBindings: prepared.toolBindings,
            declaredToolBindings: prepared.declaredToolBindings,
            toolNameCatalog: prepared.toolNameCatalog
        )
        _ = try accumulator.consume(createdFrame(id: "resp_identity", createdAt: 1))
        var events: [ResponsesProviderStreamEvent] = []
        for (index, item) in nativeCalls().enumerated() {
            events += try accumulator.consume(
                responsesFrame(
                    "response.output_item.added", ["output_index": index, "item": item]
                ))
        }
        #expect(try addedIdentities(events) == expectedIdentities)
    }

    @Test("Native SSE retains an explicit namespace pair whose child resembles another wire name")
    func nativeStreamingExplicitPair() throws {
        let binding = ResponsesToolNamespaces.Binding(namespace: "workspace", name: "read_file")
        let other = ResponsesToolNamespaces.Binding(namespace: "literal", name: "workspace__read_file")
        let bindings = ["workspace__read_file": binding, "literal__workspace__read_file": other]
        var accumulator = OpenAIResponsesTurnAccumulator(
            maximumTurnBytes: 64 * 1_024, toolBindings: bindings, declaredToolBindings: bindings
        )
        _ = try accumulator.consume(createdFrame(id: "resp_identity", createdAt: 1))
        var item = nativeCalls()[1]
        item["namespace"] = "literal"
        let events = try accumulator.consume(
            responsesFrame(
                "response.output_item.added", ["output_index": 0, "item": item]
            ))
        #expect(try addedIdentities(events) == [["namespace": "literal", "name": "workspace__read_file"]])
    }

    @Test("Native projection rejects a malformed supplied namespace")
    func nativeBufferedMalformedNamespace() throws {
        let prepared = try nativePrepared()
        var call = nativeCalls()[1]
        call["namespace"] = 42
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(
            responseData(
                responseObject(
                    id: "resp_identity",
                    createdAt: 1,
                    status: "completed",
                    output: [call],
                    usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
                )))
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesWebSearch.nonStreamingResponse(
                prepared: prepared, traces: [], finalTurn: turn, usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
            )
        }
    }

    @Test("Native SSE rejects a completed call that changes the supplied namespace")
    func nativeStreamingChangedPair() throws {
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 64 * 1_024)
        _ = try accumulator.consume(createdFrame(id: "resp_identity", createdAt: 1))
        var call = nativeCalls()[0]
        call["namespace"] = "workspace"
        _ = try accumulator.consume(responsesFrame("response.output_item.added", ["output_index": 0, "item": call]))
        _ = try accumulator.consume(
            responsesFrame(
                "response.function_call_arguments.done", ["output_index": 0, "item_id": "fc_0", "arguments": "{}"]
            ))
        call["namespace"] = "other"
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try accumulator.consume(responsesFrame("response.output_item.done", ["output_index": 0, "item": call]))
        }
    }

    private var expectedIdentities: [[String: String]] {
        [["name": "read_file"], ["namespace": "workspace", "name": "read_file"]]
    }

    private func requestBody() throws -> Data {
        try chatJSONData([
            "model": "client-model",
            "input": "Read the file.",
            "tools": [
                ["type": "function", "name": "read_file", "parameters": ["type": "object"]],
                [
                    "type": "namespace", "name": "workspace",
                    "tools": [["type": "function", "name": "read_file", "parameters": ["type": "object"]]],
                ],
            ],
        ])
    }

    private func nativePrepared() throws -> PreparedResponsesWebSearchRequest {
        try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: requestBody(), targetModel: "upstream", configuration: .firecrawlCloud
            ))
    }

    private func chatCalls() -> [[String: Any]] {
        ["read_file", "workspace__read_file"].enumerated().map { index, name in
            ["id": "call_\(index)", "type": "function", "function": ["name": name, "arguments": "{}"]]
        }
    }

    private func nativeCalls() -> [[String: Any]] {
        ["read_file", "workspace__read_file"].enumerated().map { index, name in
            functionCallItem(
                id: "fc_\(index)", callID: "call_\(index)", name: name, arguments: "{}", status: "completed")
        }
    }

    private func identities(_ output: [[String: Any]]) -> [[String: String]] {
        output.filter { $0["type"] as? String == "function_call" }.map { item in
            item.filter { ["name", "namespace"].contains($0.key) }.compactMapValues { $0 as? String }
        }
    }

    private func addedIdentities(_ events: [ResponsesProviderStreamEvent]) throws -> [[String: String]] {
        let items = try events.compactMap { event -> [String: Any]? in
            guard case .outputItemAdded(_, let itemJSON) = event else { return nil }
            return try chatJSONObject(itemJSON)
        }
        return identities(items)
    }
}
