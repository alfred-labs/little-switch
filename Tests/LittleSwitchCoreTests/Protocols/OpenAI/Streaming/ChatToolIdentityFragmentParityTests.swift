import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Chat fragmented tool identity parity")
struct ChatToolIdentityFragmentParityTests {
    @Test("The same fragmented name accepted by the contract produces one complete public tool identity")
    func fragmentedToolName() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: chatJSONData([
                "model": "client", "input": "Read.",
                "tools": [["type": "function", "name": "read_file", "parameters": ["type": "object"]]],
            ]),
            targetModel: "upstream",
            mode: .streaming(toolStream: true))
        let frames = try [
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "tool_calls": [
                        chatToolDelta(
                            index: 0,
                            id: "call_read",
                            name: "read_",
                            arguments: "{\"path\":")
                    ]
                ])
            ]),
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "tool_calls": [
                        chatToolDelta(
                            index: 0,
                            name: "file",
                            arguments: "\"file.txt\"}")
                    ]
                ])
            ]),
            chatChunkFrame(
                choices: [
                    chatChoice(
                        delta: [:],
                        finishReason: "tool_calls")
                ],
                usage: ["prompt_tokens": 0, "completion_tokens": 0]),
            chatDoneFrame(),
        ]
        var contract = try ProviderToolContract(
            wire: .chatCompletions,
            requestBody: prepared.upstreamBody)
        for frame in frames { try contract.validateFrame(frame) }
        try contract.finish()

        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        var events: [ResponsesProviderStreamEvent] = []
        for frame in frames { events += try accumulator.consume(frame) }
        let output = try #require(chatJSONObject(accumulator.finish().rootJSON)["output"] as? [[String: Any]])
        #expect(output.count == 1)
        #expect(output.first?["name"] as? String == "read_file")
        #expect(output.first?["arguments"] as? String == "{\"path\":\"file.txt\"}")
        let added = try events.compactMap { event -> String? in
            guard case .outputItemAdded(_, let data) = event else { return nil }
            return try chatJSONObject(data)["name"] as? String
        }
        #expect(added == ["read_file"])
        let argumentNames = events.compactMap { event -> String? in
            guard case .functionArgumentsDelta(_, _, _, let name, _) = event else { return nil }
            return name
        }
        #expect(argumentNames.allSatisfy { $0 == "read_file" })
    }
}
