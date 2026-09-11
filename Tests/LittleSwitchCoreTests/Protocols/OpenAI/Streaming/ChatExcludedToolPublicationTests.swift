import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Chat excluded tool publication")
struct ChatExcludedToolPublicationTests {
    @Test("An excluded call exposes neither its identity nor its input", arguments: ["function", "custom"])
    func excludedCall(kind: String) throws {
        let prepared = try prepared(kind: kind)
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        let events = try accumulator.consume(initial(kind: kind))
        #expect(events.count == 1)
        guard let first = events.first, case .responseStarted = first else {
            Issue.record("The first provider chunk must only start the response")
            return
        }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try accumulator.consume(finish())
        }
    }

    @Test(
        "A pending excluded name can acquire its allowed namespace before publication",
        arguments: ["function", "custom"], [false, true])
    func lateNamespace(kind: String, repeatedName: Bool) throws {
        let prepared = try prepared(kind: kind)
        var identity: [String: Any] = ["namespace": "workspace"]
        if repeatedName { identity["name"] = "run" }
        let second = try continuation(kind: kind, identity: identity)
        let output = try collect(prepared: prepared, kind: kind, second: second)
        #expect(output["name"] as? String == "run")
        #expect(output["namespace"] as? String == "workspace")
        #expect(output[inputKey(kind)] as? String == "first last")
    }

    @Test(
        "Excluded prefixes can extend or repeat into the allowed identity", arguments: ["function", "custom"],
        ["_long", "run"])
    func completedPrefix(kind: String, suffix: String) throws {
        let prepared = try prepared(kind: kind, suffix: suffix)
        let second = try continuation(kind: kind, identity: ["name": suffix])
        let output = try collect(prepared: prepared, kind: kind, second: second)
        #expect(output["name"] as? String == "run" + suffix)
        #expect(output["namespace"] == nil)
        #expect(output[inputKey(kind)] as? String == "first last")
    }

    private func collect(
        prepared: PreparedResponsesChatCompletionsRequest, kind: String, second: ServerSentEventFrame
    ) throws -> [String: Any] {
        var contract = try ProviderToolContract(
            wire: .chatCompletions,
            requestBody: prepared.upstreamBody,
            declaredToolBindings: prepared.declaredToolBindings,
            toolNameCatalog: prepared.toolNameCatalog)
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        let first = try initial(kind: kind)
        try contract.validateFrame(first)
        #expect(try accumulator.consume(first).count == 1)
        var published: [[String: Any]] = []
        for frame in try [second, finish(), chatDoneFrame()] {
            try contract.validateFrame(frame)
            for event in try accumulator.consume(frame) {
                if case .outputItemAdded(_, let item) = event { published.append(try chatJSONObject(item)) }
            }
        }
        try contract.finish()
        let output = try #require(chatJSONObject(accumulator.finish().rootJSON)["output"] as? [[String: Any]])
        let call = try #require(output.first)
        #expect(output.count == 1)
        #expect(published.count == 1)
        #expect(published.first?["name"] as? String == call["name"] as? String)
        #expect(published.first?["namespace"] as? String == call["namespace"] as? String)
        return call
    }

    private func prepared(kind: String, suffix: String? = nil) throws -> PreparedResponsesChatCompletionsRequest {
        let selected: [String: Any]
        let declaration: [String: Any]
        if let suffix {
            selected = ["type": kind, "name": "run" + suffix]
            declaration = selected
        } else {
            selected = ["type": kind, "name": "run", "namespace": "workspace"]
            declaration = ["type": "namespace", "name": "workspace", "tools": [["type": kind, "name": "run"]]]
        }
        return try OpenAIResponsesChatCompletions.prepare(
            body: chatJSONData([
                "model": "route", "input": "Use the selected tool", "stream": true,
                "tools": [["type": kind, "name": "run"], declaration],
                "tool_choice": ["type": "allowed_tools", "mode": "auto", "tools": [selected]],
            ]),
            targetModel: "upstream",
            mode: .streaming(toolStream: true))
    }

    private func initial(kind: String) throws -> ServerSentEventFrame {
        try chatChunkFrame(choices: [
            chatChoice(delta: [
                "tool_calls": [
                    [
                        "index": 0, "id": "call", "type": kind, kind: ["name": "run", inputKey(kind): "first"],
                    ]
                ]
            ])
        ])
    }

    private func continuation(kind: String, identity: [String: Any]) throws -> ServerSentEventFrame {
        var fields = identity
        fields[inputKey(kind)] = " last"
        return try chatChunkFrame(choices: [chatChoice(delta: ["tool_calls": [["index": 0, kind: fields]]])])
    }

    private func finish() throws -> ServerSentEventFrame {
        try chatChunkFrame(
            choices: [chatChoice(delta: [:], finishReason: "tool_calls")],
            usage: ["prompt_tokens": 0, "completion_tokens": 0])
    }

    private func inputKey(_ kind: String) -> String { kind == "function" ? "arguments" : "input" }
}
