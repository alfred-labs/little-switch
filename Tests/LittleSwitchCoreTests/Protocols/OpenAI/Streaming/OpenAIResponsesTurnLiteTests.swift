import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses Lite turn accumulation")
struct OpenAIResponsesTurnLiteTests {
    @Test("Completed stream items survive an empty Lite terminal in output order", arguments: [false, true])
    func completedOutput(lite: Bool) throws {
        let items = [
            functionCallItem(id: "fc_first", callID: "call_first", name: "read", arguments: "{}", status: "completed"),
            functionCallItem(
                id: "fc_second", callID: "call_second", name: "write", arguments: "{}", status: "completed"),
        ]
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 32_768, privateToolName: nil)
        _ = try accumulator.consume(createdFrame(id: "resp_lite", createdAt: 1))
        for (index, item) in items.enumerated() {
            var started = item
            started["status"] = "in_progress"
            started["arguments"] = ""
            _ = try accumulator.consume(
                responsesFrame("response.output_item.added", ["output_index": index, "item": started]))
        }
        for (index, item) in items.enumerated().reversed() {
            _ = try accumulator.consume(
                responsesFrame(
                    "response.function_call_arguments.done",
                    ["output_index": index, "item_id": try #require(item["id"] as? String), "arguments": "{}"]
                ))
            _ = try accumulator.consume(
                responsesFrame("response.output_item.done", ["output_index": index, "item": item]))
        }
        var expectedItems = items
        if !lite { expectedItems[0]["provider_metadata"] = ["final": true] }
        let expected = responseObject(
            id: "resp_lite",
            createdAt: 1,
            status: "completed",
            output: expectedItems,
            usage: ResponsesUsage(inputTokens: 20, outputTokens: 5))
        var terminal = expected
        if lite { terminal["output"] = [] }
        let terminalEvents = try accumulator.consume(responsesFrame("response.completed", ["response": terminal]))
        #expect(terminalEvents == [.terminal(status: .completed, responseJSON: try responsesStreamData(terminal))])
        let turn = try accumulator.finish()
        #expect(try responsesStreamData(responsesStreamObject(turn.rootJSON)) == responsesStreamData(expected))
        #expect(turn.usage == ResponsesUsage(inputTokens: 20, outputTokens: 5))
    }
}
