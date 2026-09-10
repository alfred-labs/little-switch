import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses reasoning passthrough")
struct ResponsesReasoningPassthroughTests {
    private func accumulator(
        openingItem item: [String: Any]
    ) throws -> OpenAIResponsesTurnAccumulator {
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 1_000_000)
        _ = try accumulator.consume(
            responsesFrame(
                "response.created",
                [
                    "response": responseObject(
                        id: "resp_provider",
                        createdAt: 40,
                        status: "in_progress",
                        output: [],
                        usage: nil
                    )
                ]
            )
        )
        _ = try accumulator.consume(
            responsesFrame(
                "response.output_item.added",
                ["output_index": 0, "item": item]
            )
        )
        return accumulator
    }

    private var reasoningItem: [String: Any] {
        ["id": "rs_1", "type": "reasoning", "summary": [], "content": []]
    }

    private var messageItem: [String: Any] {
        ["id": "msg_1", "type": "message", "role": "assistant", "content": []]
    }

    @Test("A reasoning text delta passes through without a declared content part")
    func reasoningTextDeltaPassesThrough() throws {
        var accumulator = try accumulator(openingItem: reasoningItem)

        let events = try accumulator.consume(
            responsesFrame(
                "response.reasoning_text.delta",
                [
                    "output_index": 0,
                    "item_id": "rs_1",
                    "content_index": 0,
                    "delta": "We",
                ]
            )
        )

        #expect(events.count == 1)
    }

    @Test("A message content part reference is still validated")
    func messageContentPartStillValidated() throws {
        var accumulator = try accumulator(openingItem: messageItem)

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try accumulator.consume(
                responsesFrame(
                    "response.custom_provider.delta",
                    [
                        "output_index": 0,
                        "item_id": "msg_1",
                        "content_index": 3,
                        "delta": "x",
                    ]
                )
            )
        }
    }

    @Test("The full reasoning-then-message sequence is accepted")
    func fullReasoningSequence() throws {
        var accumulator = try accumulator(openingItem: reasoningItem)

        _ = try accumulator.consume(
            responsesFrame(
                "response.reasoning_text.delta",
                ["output_index": 0, "item_id": "rs_1", "content_index": 0, "delta": "We"]
            )
        )
        _ = try accumulator.consume(
            responsesFrame(
                "response.reasoning_text.done",
                ["output_index": 0, "item_id": "rs_1", "content_index": 0, "text": "We"]
            )
        )
        _ = try accumulator.consume(
            responsesFrame(
                "response.output_item.done",
                [
                    "output_index": 0,
                    "item": [
                        "id": "rs_1",
                        "type": "reasoning",
                        "summary": [],
                        "content": [["type": "reasoning_text", "text": "We"]],
                        "status": "completed",
                    ],
                ]
            )
        )
        _ = try accumulator.consume(
            responsesFrame(
                "response.output_item.added",
                ["output_index": 1, "item": messageItem]
            )
        )

        #expect(Bool(true))
    }

    @Test("A malformed content index is rejected even on a reasoning item")
    func malformedContentIndexRejected() throws {
        var accumulator = try accumulator(openingItem: reasoningItem)

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try accumulator.consume(
                responsesFrame(
                    "response.reasoning_text.delta",
                    [
                        "output_index": 0,
                        "item_id": "rs_1",
                        "content_index": "not-a-number",
                        "delta": "We",
                    ]
                )
            )
        }
    }

    @Test("A dangling output index is still rejected for reasoning items")
    func danglingOutputIndexStillRejected() throws {
        var accumulator = try accumulator(openingItem: reasoningItem)

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try accumulator.consume(
                responsesFrame(
                    "response.reasoning_text.delta",
                    [
                        "output_index": 7,
                        "item_id": "rs_1",
                        "content_index": 0,
                        "delta": "We",
                    ]
                )
            )
        }
    }
}
