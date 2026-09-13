import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Stream wire identities and terminal validation")
struct StreamWireValidationTests {
    @Test func chatRejectsRepeatedIndicesWithinOneFrame() throws {
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: try liveChatPrepared())
        let frame = try chatChunkFrame(choices: [chatChoice(delta: [:]), chatChoice(delta: [:])])
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) { try accumulator.consume(frame) }
    }

    @Test(arguments: ["id", "model"])
    func chatRequiresNonemptyStreamIdentity(field: String) throws {
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: try liveChatPrepared())
        let frame = try chatChunkFrame(id: field == "id" ? "" : "chat", model: field == "model" ? "" : "m", choices: [])
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) { try accumulator.consume(frame) }
    }

    @Test func responsesRejectsEmptyFutureEventTags() throws {
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try accumulator.consume(createdFrame(id: "resp", createdAt: 1))
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try accumulator.consume(responsesFrame("", [:]))
        }
    }

    @Test func completedItemCannotReplaceItsAnnouncedIdentity() throws {
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try accumulator.consume(createdFrame(id: "resp", createdAt: 1))
        let added: [String: Any] = ["type": "reasoning", "id": "first", "summary": []]
        _ = try accumulator.consume(responsesFrame("response.output_item.added", ["output_index": 0, "item": added]))
        let done: [String: Any] = ["type": "reasoning", "id": "second", "summary": []]
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try accumulator.consume(responsesFrame("response.output_item.done", ["output_index": 0, "item": done]))
        }
    }

    @Test func aFailedTerminalCannotCarryAnEmptyErrorCode() throws {
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try accumulator.consume(createdFrame(id: "resp", createdAt: 1))
        let response: [String: Any] = [
            "id": "resp", "object": "response", "status": "failed",
            "error": ["code": "", "message": "Synthetic failure"],
        ]
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try accumulator.consume(responsesFrame("response.failed", ["response": response]))
        }
    }

    @Test(arguments: [
        #"{"choices":[]}"#,
        #"{"choices":[{"finish_reason":"function_call","message":{}}]}"#,
    ])
    func bufferedChatRequiresASupportedTerminalChoice(body: String) throws {
        let data = Data(body.utf8)
        let prepared = try liveChatPrepared()
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            try OpenAIResponsesChatCompletions.terminalStatus(responseBody: data)
        }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            try OpenAIResponsesChatCompletions.project(responseBody: data, prepared: prepared)
        }
    }

    @Test func bufferedChatRejectsAnEmptyCallIdentity() throws {
        let data = Data(
            #"{"choices":[{"finish_reason":"tool_calls","message":{"tool_calls":[{"type":"function","id":"","function":{"name":"run","arguments":"{}"}}]}}]}"#
                .utf8)
        let prepared = try liveChatPrepared()
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            try OpenAIResponsesChatCompletions.project(responseBody: data, prepared: prepared)
        }
    }
}
