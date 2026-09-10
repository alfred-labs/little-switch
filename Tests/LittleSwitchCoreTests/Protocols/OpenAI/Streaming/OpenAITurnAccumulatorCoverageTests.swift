import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI turn accumulator coverage")
struct OpenAITurnAccumulatorCoverageTests {
    @Test("Top-level lifecycle rejects missing types and out-of-order passthrough")
    func topLevelEdges() throws {
        var missingType = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingType.consume(
                ServerSentEventFrame(
                    event: nil,
                    data: responseData([:]),
                    terminal: false
                ))
        }

        for type in ["error", "response.provider_private"] {
            var beforeStart = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try beforeStart.consume(responsesFrame(type, [:]))
            }
        }

        var invalidCreatedStatus = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try invalidCreatedStatus.consume(
                responsesFrame(
                    "response.created",
                    [
                        "response": [
                            "id": "resp", "object": "response", "status": "completed",
                            "output": [],
                        ]
                    ]
                ))
        }
    }

    @Test("Output item and content metadata remain stable")
    // Each fresh accumulator isolates one fail-closed transition.
    // swiftlint:disable:next function_body_length
    func outputAndContentEdges() throws {
        var duplicateOutput = try coverageStartedTurnAccumulator()
        _ = try duplicateOutput.consume(
            responsesFrame(
                "response.output_item.added",
                ["output_index": 0, "item": coverageMessageItem(id: "msg")]
            ))
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try duplicateOutput.consume(
                responsesFrame(
                    "response.output_item.added",
                    ["output_index": 0, "item": coverageMessageItem(id: "other")]
                ))
        }

        var invalidMessageContent = try coverageStartedTurnAccumulator()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try invalidMessageContent.consume(
                responsesFrame(
                    "response.output_item.added",
                    [
                        "output_index": 0,
                        "item": [
                            "id": "msg", "type": "message", "content": "bad",
                        ],
                    ]
                ))
        }

        var missingDoneItem = try coverageStartedTurnAccumulator()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingDoneItem.consume(
                responsesFrame(
                    "response.output_item.done",
                    ["output_index": 0, "item": coverageMessageItem(id: "msg")]
                ))
        }

        var mismatchedFunction = try coverageStartedTurnAccumulator()
        _ = try mismatchedFunction.consume(
            responsesFrame(
                "response.output_item.added",
                [
                    "output_index": 0,
                    "item": functionCallItem(
                        id: "fc",
                        callID: "call",
                        name: "read",
                        arguments: "",
                        status: "in_progress"
                    ),
                ]
            ))
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try mismatchedFunction.consume(
                responsesFrame(
                    "response.output_item.done",
                    [
                        "output_index": 0,
                        "item": functionCallItem(
                            id: "fc",
                            callID: "other",
                            name: "read",
                            arguments: "",
                            status: "completed"
                        ),
                    ]
                ))
        }

        var missingContentItem = try coverageStartedTurnAccumulator()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingContentItem.consume(
                responsesFrame(
                    "response.content_part.added",
                    [
                        "output_index": 0,
                        "content_index": 0,
                        "item_id": "msg",
                        "part": outputTextPart(""),
                    ]
                ))
        }

        var malformedTextPart = try coverageStartedTurnAccumulator()
        _ = try malformedTextPart.consume(
            responsesFrame(
                "response.output_item.added",
                ["output_index": 0, "item": coverageMessageItem(id: "msg")]
            ))
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try malformedTextPart.consume(
                responsesFrame(
                    "response.content_part.added",
                    [
                        "output_index": 0,
                        "content_index": 0,
                        "item_id": "msg",
                        "part": ["type": "output_text"],
                    ]
                ))
        }

        var missingDeltaReference = try coverageStartedTurnAccumulator()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingDeltaReference.consume(
                responsesFrame(
                    "response.output_text.delta",
                    [
                        "output_index": 0,
                        "content_index": 0,
                        "item_id": "msg",
                        "delta": "x",
                    ]
                ))
        }

        var duplicateTextDone = try coverageTextTurnAccumulator()
        _ = try duplicateTextDone.consume(
            responsesFrame(
                "response.output_text.done",
                coverageTextReference().merging(["text": "x"]) { _, new in new }
            ))
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try duplicateTextDone.consume(
                responsesFrame(
                    "response.output_text.done",
                    coverageTextReference().merging(["text": "x"]) { _, new in new }
                ))
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try duplicateTextDone.consume(
                responsesFrame(
                    "response.output_text.delta",
                    coverageTextReference().merging(["delta": "late"]) { _, new in new }
                ))
        }

        var missingPartDone = try coverageStartedTurnAccumulator()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingPartDone.consume(
                responsesFrame(
                    "response.content_part.done",
                    coverageTextReference().merging(["part": outputTextPart("x")]) { _, new in new }
                ))
        }

        var mismatchedPartDone = try coverageTextTurnAccumulator()
        _ = try mismatchedPartDone.consume(
            responsesFrame(
                "response.output_text.done",
                coverageTextReference().merging(["text": "expected"]) { _, new in new }
            ))
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try mismatchedPartDone.consume(
                responsesFrame(
                    "response.content_part.done",
                    coverageTextReference().merging(["part": outputTextPart("other")]) { _, new in new }
                ))
        }

        var wrongPartType = try coverageTextTurnAccumulator()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try wrongPartType.consume(
                responsesFrame(
                    "response.content_part.done",
                    coverageTextReference().merging([
                        "part": ["type": "refusal", "refusal": "No"]
                    ]) { _, new in new }
                ))
        }

        var validPassthrough = try coverageTextTurnAccumulator()
        #expect(
            try !validPassthrough.consume(
                responsesFrame(
                    "response.provider_private",
                    coverageTextReference()
                )
            ).isEmpty
        )
    }
}

extension OpenAITurnAccumulatorCoverageTests {
    @Test("Function and passthrough references reject conflicting metadata")
    // The cases intentionally exercise all optional reference fields.
    func functionAndPassthroughEdges() throws {
        var missingFunction = try coverageStartedTurnAccumulator()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingFunction.consume(
                responsesFrame(
                    "response.function_call_arguments.done",
                    ["output_index": 0, "item_id": "fc", "arguments": "{}"]
                ))
        }

        for metadata: [String: Any] in [
            ["call_id": "other"],
            ["name": "other"],
        ] {
            var function = try coverageFunctionTurnAccumulator()
            var payload: [String: Any] = [
                "output_index": 0,
                "item_id": "fc",
                "delta": "{}",
            ]
            payload.merge(metadata) { _, new in new }
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try function.consume(
                    responsesFrame(
                        "response.function_call_arguments.delta",
                        payload
                    ))
            }
        }

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try responsesFunctionMetadata([:], required: true)
        }

        let passthroughCases: [[String: Any]] = [
            ["output_index": -1],
            ["output_index": 0],
        ]
        for payload in passthroughCases {
            var accumulator = try coverageStartedTurnAccumulator()
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try accumulator.consume(
                    responsesFrame(
                        "response.provider_private",
                        payload
                    ))
            }
        }

        var wrongItem = try coverageTextTurnAccumulator()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try wrongItem.consume(
                responsesFrame(
                    "response.provider_private",
                    ["output_index": 0, "item_id": "other"]
                ))
        }

        var wrongContent = try coverageTextTurnAccumulator()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try wrongContent.consume(
                responsesFrame(
                    "response.provider_private",
                    ["output_index": 0, "item_id": "msg", "content_index": 1]
                ))
        }
    }

    @Test("Terminal responses reject incomplete state and malformed failures")
    func terminalEdges() throws {
        var incompleteOutput = try coverageStartedTurnAccumulator()
        _ = try incompleteOutput.consume(
            responsesFrame(
                "response.output_item.added",
                [
                    "output_index": 0,
                    "item": [
                        "id": "msg", "type": "message", "role": "assistant",
                        "status": "in_progress", "content": [],
                    ],
                ]
            ))
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try incompleteOutput.consume(
                responsesFrame(
                    "response.completed",
                    [
                        "response": responseObject(
                            id: "resp",
                            createdAt: 1,
                            status: "completed",
                            output: [],
                            usage: .init(inputTokens: 0, outputTokens: 0)
                        )
                    ]
                ))
        }

        var malformedFailure = try coverageStartedTurnAccumulator()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try malformedFailure.consume(
                responsesFrame(
                    "response.failed",
                    [
                        "response": [
                            "id": "resp", "object": "response", "status": "failed",
                            "error": ["message": "no code"],
                        ]
                    ]
                ))
        }

        var missingUsage = try coverageStartedTurnAccumulator()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingUsage.consume(
                responsesFrame(
                    "response.completed",
                    [
                        "response": [
                            "id": "resp", "object": "response", "status": "completed",
                            "output": [], "usage": NSNull(),
                        ]
                    ]
                ))
        }

        var terminalPhase = try coverageStartedTurnAccumulator()
        _ = try terminalPhase.consume(
            responsesFrame(
                "response.completed",
                [
                    "response": responseObject(
                        id: "resp",
                        createdAt: 1,
                        status: "completed",
                        output: [],
                        usage: .init(inputTokens: 0, outputTokens: 0)
                    )
                ]
            ))
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try terminalPhase.consume(
                responsesFrame(
                    "response.output_text.done",
                    coverageTextReference().merging(["text": "late"]) { _, new in new }
                ))
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try terminalPhase.consume(
                responsesFrame(
                    "response.content_part.done",
                    coverageTextReference().merging(["part": outputTextPart("late")]) { _, new in new }
                ))
        }
    }
}

private func coverageStartedTurnAccumulator() throws -> OpenAIResponsesTurnAccumulator {
    var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 32_768)
    _ = try accumulator.consume(createdFrame(id: "resp", createdAt: 1))
    return accumulator
}

private func coverageTextTurnAccumulator() throws -> OpenAIResponsesTurnAccumulator {
    var accumulator = try coverageStartedTurnAccumulator()
    _ = try accumulator.consume(
        responsesFrame(
            "response.output_item.added",
            ["output_index": 0, "item": coverageMessageItem(id: "msg")]
        ))
    _ = try accumulator.consume(
        responsesFrame(
            "response.content_part.added",
            coverageTextReference().merging(["part": outputTextPart("")]) { _, new in new }
        ))
    return accumulator
}

private func coverageFunctionTurnAccumulator() throws -> OpenAIResponsesTurnAccumulator {
    var accumulator = try coverageStartedTurnAccumulator()
    _ = try accumulator.consume(
        responsesFrame(
            "response.output_item.added",
            [
                "output_index": 0,
                "item": functionCallItem(
                    id: "fc",
                    callID: "call",
                    name: "read",
                    arguments: "",
                    status: "in_progress"
                ),
            ]
        ))
    return accumulator
}

private func coverageMessageItem(id: String) -> [String: Any] {
    [
        "id": id,
        "type": "message",
        "status": "in_progress",
        "role": "assistant",
        "content": [],
    ]
}

private func coverageTextReference() -> [String: Any] {
    ["output_index": 0, "content_index": 0, "item_id": "msg"]
}
