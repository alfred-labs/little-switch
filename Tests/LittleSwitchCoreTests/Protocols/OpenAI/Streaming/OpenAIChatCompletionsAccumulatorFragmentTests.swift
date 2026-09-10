import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Chat Completions accumulator fragments")
struct ChatAccumulatorFragmentTests {
    @Test("Thousands of tiny text and tool fragments preserve order and final values")
    func highFragmentTurn() throws {
        let fragmentCount = 2_048
        let textFragments = (0..<fragmentCount).map { index in
            ["A", "é", "🙂"][index % 3]
        }
        let argumentFragments =
            ["{\"query\":\""] + Array(repeating: "x", count: fragmentCount) + ["\"}"]
        let expectedText = textFragments.joined()
        let expectedArguments = argumentFragments.joined()

        var accumulator = OpenAIChatCompletionsAccumulator(prepared: try liveChatPrepared())
        var events: [ResponsesProviderStreamEvent] = []
        var expectedDeltas: [String] = []

        for offset in 0..<max(textFragments.count, argumentFragments.count) {
            var delta: [String: Any] = [:]
            if offset == 0 {
                delta["role"] = "assistant"
            }
            if offset < textFragments.count {
                let fragment = textFragments[offset]
                delta["content"] = fragment
                expectedDeltas.append("text:\(fragment)")
            }
            if offset < argumentFragments.count {
                let fragment = argumentFragments[offset]
                delta["tool_calls"] = [
                    chatToolDelta(
                        index: 0,
                        id: offset == 0 ? "call_search" : nil,
                        name: offset == 0 ? "web_search" : nil,
                        arguments: fragment
                    )
                ]
                expectedDeltas.append("arguments:\(fragment)")
            }
            events += try accumulator.consume(
                chatChunkFrame(choices: [chatChoice(delta: delta)])
            )
        }
        events += try accumulator.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: [:], finishReason: "tool_calls")
            ])
        )
        events += try accumulator.consume(
            chatChunkFrame(
                choices: [],
                usage: [
                    "prompt_tokens": 8,
                    "completion_tokens": fragmentCount,
                    "total_tokens": fragmentCount + 8,
                ]
            )
        )
        events += try accumulator.consume(chatDoneFrame())
        let turn = try accumulator.finish()

        let emittedDeltas = events.compactMap { event -> String? in
            if let text = event.outputTextDelta {
                return "text:\(text)"
            }
            if let arguments = event.functionDelta?.value {
                return "arguments:\(arguments)"
            }
            return nil
        }
        #expect(emittedDeltas == expectedDeltas)
        #expect(
            events.compactMap(\.functionDone).last?.value
                == expectedArguments
        )

        let response = try chatJSONObject(turn.rootJSON)
        let output = try #require(response["output"] as? [[String: Any]])
        let messageContent = try #require(output[0]["content"] as? [[String: Any]])
        #expect(messageContent[0]["text"] as? String == expectedText)
        #expect(output[1]["arguments"] as? String == expectedArguments)
        #expect(turn.webSearchCall?.query == String(repeating: "x", count: fragmentCount))
        #expect(events.last?.terminalStatus == .completed)
    }
}
