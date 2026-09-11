import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Chat tool streaming boundaries")
struct ChatToolStreamingBoundaryTests {
    @Test(
        "Repeated custom name fragments preserve a complete or growing identity", arguments: [false, true],
        [false, true])
    func repeatedName(completePrefix: Bool, namespaced: Bool) throws {
        let name = completePrefix ? "read" : "readread"
        let names = completePrefix ? ["read", "read_file"] : [name]
        let children = names.map { ["type": "custom", "name": $0] }
        let tools: [[String: Any]] =
            namespaced ? [["type": "namespace", "name": "workspace", "tools": children]] : children
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: chatJSONData(["model": "route", "input": "Read", "tools": tools]),
            targetModel: "upstream")
        var initial: [String: Any] = ["name": "read", "input": "first"]
        if namespaced { initial["namespace"] = "workspace" }
        let frames = try [
            chatChunkFrame(choices: [
                chatChoice(delta: ["tool_calls": [["index": 0, "id": "call", "type": "custom", "custom": initial]]])
            ]),
            chatChunkFrame(choices: [
                chatChoice(delta: ["tool_calls": [["index": 0, "custom": ["name": "read", "input": " last"]]]])
            ]),
            chatChunkFrame(
                choices: [chatChoice(delta: [:], finishReason: "tool_calls")],
                usage: ["prompt_tokens": 0, "completion_tokens": 0]),
            chatDoneFrame(),
        ]
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        var contract = try ProviderToolContract(
            wire: .chatCompletions,
            requestBody: prepared.upstreamBody,
            declaredToolBindings: prepared.declaredToolBindings,
            toolNameCatalog: prepared.toolNameCatalog)
        var events: [ResponsesProviderStreamEvent] = []
        for frame in frames {
            try contract.validateFrame(frame)
            events += try accumulator.consume(frame)
        }
        try contract.finish()
        let output = try #require(chatJSONObject(accumulator.finish().rootJSON)["output"] as? [[String: Any]])
        let call = try #require(output.first)
        #expect(output.count == 1)
        #expect(call["name"] as? String == name)
        #expect(call["namespace"] as? String == (namespaced ? "workspace" : nil))
        #expect(call["input"] as? String == "first last")
        let published = try events.compactMap { event -> [String: Any]? in
            guard case .outputItemAdded(_, let data) = event else { return nil }
            return try chatJSONObject(data)
        }
        #expect(published.count == 1)
        #expect(published.first?["name"] as? String == name)
        let fragments = events.compactMap { event -> String? in
            guard case .customInputDelta(_, _, _, _, let delta) = event else { return nil }
            return delta
        }
        #expect(fragments == ["first", " last"])
    }

    @Test("Malformed continuation payloads cannot change a started tool", arguments: [false, true])
    func malformedContinuation(name: Bool) throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: chatJSONData(["model": "route", "input": "Read", "tools": [["type": "custom", "name": "read"]]]),
            targetModel: "upstream")
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try accumulator.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "tool_calls": [
                        ["index": 0, "id": "call", "type": "custom", "custom": ["name": "read", "input": "first"]]
                    ]
                ])
            ]))
        let input: Any = name ? ["name": 42] : 42
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try accumulator.consume(
                chatChunkFrame(choices: [chatChoice(delta: ["tool_calls": [["index": 0, "custom": input]]])]))
        }
    }
}
