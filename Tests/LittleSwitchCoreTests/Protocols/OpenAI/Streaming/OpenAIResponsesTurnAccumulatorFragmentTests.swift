import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses turn accumulator fragments")
struct ResponsesAccumulatorFragmentTests {
    @Test("Thousands of native text and tool fragments preserve order and final values")
    func highFragmentTurn() throws {
        let fragmentCount = 2_048
        let textFragments = (0..<fragmentCount).map { index in
            ["A", "é", "🙂"][index % 3]
        }
        let argumentFragments =
            ["{\"query\":\""] + Array(repeating: "x", count: fragmentCount) + ["\"}"]
        let expectedText = textFragments.joined()
        let expectedArguments = argumentFragments.joined()
        let messageStart: [String: Any] = [
            "id": "msg_fragments",
            "type": "message",
            "status": "in_progress",
            "role": "assistant",
            "content": [],
        ]
        let messageDone: [String: Any] = [
            "id": "msg_fragments",
            "type": "message",
            "status": "completed",
            "role": "assistant",
            "content": [outputTextPart(expectedText)],
        ]
        let functionStart = functionCallItem(
            id: "fc_fragments",
            callID: "call_fragments",
            name: "web_search",
            arguments: "",
            status: "in_progress"
        )
        let functionDone = functionCallItem(
            id: "fc_fragments",
            callID: "call_fragments",
            name: "web_search",
            arguments: expectedArguments,
            status: "completed"
        )

        var frames = try highFragmentStartFrames(
            messageStart: messageStart,
            functionStart: functionStart
        )
        var expectedDeltas: [String] = []
        for offset in 0..<max(textFragments.count, argumentFragments.count) {
            if offset < textFragments.count {
                let fragment = textFragments[offset]
                frames.append(
                    try responsesFrame(
                        "response.output_text.delta",
                        [
                            "output_index": 0,
                            "content_index": 0,
                            "item_id": "msg_fragments",
                            "delta": fragment,
                        ]
                    )
                )
                expectedDeltas.append("text:\(fragment)")
            }
            if offset < argumentFragments.count {
                let fragment = argumentFragments[offset]
                frames.append(
                    try responsesFrame(
                        "response.function_call_arguments.delta",
                        [
                            "output_index": 1,
                            "item_id": "fc_fragments",
                            "delta": fragment,
                        ]
                    )
                )
                expectedDeltas.append("arguments:\(fragment)")
            }
        }
        frames += try highFragmentDoneFrames(
            messageDone: messageDone,
            functionDone: functionDone,
            text: expectedText,
            arguments: expectedArguments,
            fragmentCount: fragmentCount
        )

        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 8 * 1_024 * 1_024)
        var events: [ResponsesProviderStreamEvent] = []
        for frame in frames {
            events += try accumulator.consume(frame)
        }
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
        #expect(events.compactMap(\.functionDone).last?.value == expectedArguments)
        #expect(turn.webSearchCall?.query == String(repeating: "x", count: fragmentCount))
        #expect(events.last?.terminalStatus == .completed)
    }
}

private func highFragmentStartFrames(
    messageStart: [String: Any],
    functionStart: [String: Any]
) throws -> [ServerSentEventFrame] {
    try [
        createdFrame(id: "resp_fragments", createdAt: 200),
        responsesFrame(
            "response.output_item.added",
            ["output_index": 0, "item": messageStart]
        ),
        responsesFrame(
            "response.content_part.added",
            [
                "output_index": 0,
                "content_index": 0,
                "item_id": "msg_fragments",
                "part": outputTextPart(""),
            ]
        ),
        responsesFrame(
            "response.output_item.added",
            ["output_index": 1, "item": functionStart]
        ),
    ]
}

private func highFragmentDoneFrames(
    messageDone: [String: Any],
    functionDone: [String: Any],
    text: String,
    arguments: String,
    fragmentCount: Int
) throws -> [ServerSentEventFrame] {
    let terminal = responseObject(
        id: "resp_fragments",
        createdAt: 200,
        status: "completed",
        output: [messageDone, functionDone],
        usage: ResponsesUsage(inputTokens: 8, outputTokens: fragmentCount)
    )
    return try [
        responsesFrame(
            "response.output_text.done",
            [
                "output_index": 0,
                "content_index": 0,
                "item_id": "msg_fragments",
                "text": text,
            ]
        ),
        responsesFrame(
            "response.content_part.done",
            [
                "output_index": 0,
                "content_index": 0,
                "item_id": "msg_fragments",
                "part": outputTextPart(text),
            ]
        ),
        responsesFrame(
            "response.output_item.done",
            ["output_index": 0, "item": messageDone]
        ),
        responsesFrame(
            "response.function_call_arguments.done",
            [
                "output_index": 1,
                "item_id": "fc_fragments",
                "arguments": arguments,
            ]
        ),
        responsesFrame(
            "response.output_item.done",
            ["output_index": 1, "item": functionDone]
        ),
        responsesFrame("response.completed", ["response": terminal]),
    ]
}
