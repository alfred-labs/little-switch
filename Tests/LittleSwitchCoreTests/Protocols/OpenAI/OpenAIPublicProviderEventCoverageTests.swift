import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI public provider event coverage")
struct OpenAIPublicProviderEventCoverageTests {
    @Test("Provider item lifecycle rejects invalid state and metadata")
    func itemLifecycleEdges() throws {
        var activeTurn = try coverageProviderSession()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try activeTurn.beginProviderTurn(responseData(["id": "other"]))
        }

        var missingID = try coverageProviderSession()
        missingID.providerTurnActive = false
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingID.beginProviderTurn(responseData([:]))
        }

        var invalidIndex = try coverageProviderSession()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try invalidIndex.consumeOutputItemAdded(
                outputIndex: -1,
                itemJSON: responseData(coverageMessage(id: "msg"))
            )
        }

        var malformedItem = try coverageProviderSession()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try malformedItem.consumeOutputItemAdded(
                outputIndex: 0,
                itemJSON: responseData(["type": "message"])
            )
        }

        var duplicateID = try coverageProviderSession()
        duplicateID.usedPublicItemIDs.insert("msg")
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try duplicateID.consumeOutputItemAdded(
                outputIndex: 0,
                itemJSON: responseData(coverageMessage(id: "msg"))
            )
        }

        var missingMapping = try coverageProviderSession()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingMapping.consumeOutputItemDone(
                outputIndex: 0,
                itemJSON: responseData(coverageMessage(id: "msg", status: "completed"))
            )
        }

        var mismatchedItem = try coverageProviderSession()
        _ = try mismatchedItem.consumeOutputItemAdded(
            outputIndex: 0,
            itemJSON: responseData(coverageMessage(id: "msg"))
        )
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try mismatchedItem.consumeOutputItemDone(
                outputIndex: 0,
                itemJSON: responseData(coverageMessage(id: "other", status: "completed"))
            )
        }

        var mismatchedFunction = try coverageProviderSession()
        _ = try mismatchedFunction.consumeOutputItemAdded(
            outputIndex: 0,
            itemJSON: responseData(
                functionCallItem(
                    id: "fc",
                    callID: "call",
                    name: "read",
                    arguments: "",
                    status: "in_progress"
                ))
        )
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try mismatchedFunction.consumeOutputItemDone(
                outputIndex: 0,
                itemJSON: responseData(
                    functionCallItem(
                        id: "fc",
                        callID: "other",
                        name: "read",
                        arguments: "{}",
                        status: "completed"
                    ))
            )
        }
    }
}

extension OpenAIPublicProviderEventCoverageTests {
    @Test("Content lifecycle handles overflow and private mappings")
    func contentLifecycleEdges() throws {
        var missingOutput = try coverageProviderSession()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingOutput.consumeContentPartAdded(
                outputIndex: 0,
                contentIndex: 0,
                itemID: "msg",
                partJSON: responseData(outputTextPart(""))
            )
        }

        var malformedPart = try coverageProviderSession()
        malformedPart.providerOutput[0] = coverageOutputMapping(id: "msg", type: "message")
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try malformedPart.consumeContentPartAdded(
                outputIndex: 0,
                contentIndex: 0,
                itemID: "msg",
                partJSON: responseData([:])
            )
        }

        var overflow = try coverageProviderSession()
        var overflowMapping = coverageOutputMapping(id: "msg", type: "message")
        overflowMapping.nextContentIndex = Int.max
        overflow.providerOutput[0] = overflowMapping
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try overflow.consumeContentPartAdded(
                outputIndex: 0,
                contentIndex: 0,
                itemID: "msg",
                partJSON: responseData(outputTextPart(""))
            )
        }

        var privateContent = try coverageProviderSession()
        var privateMapping = coverageOutputMapping(
            id: "fc_private",
            type: "function_call",
            name: "web_search",
            callID: "call",
            publicIndex: nil,
            isPrivateSearch: true
        )
        privateMapping.content[0] = .init(publicIndex: 0, type: "output_text")
        privateContent.providerOutput[0] = privateMapping
        #expect(
            try privateContent.consumeOutputTextDelta(
                outputIndex: 0,
                contentIndex: 0,
                itemID: "fc_private",
                delta: "private"
            ).isEmpty
        )
        #expect(
            try privateContent.consumeOutputTextDone(
                outputIndex: 0,
                contentIndex: 0,
                itemID: "fc_private",
                text: "private"
            ).isEmpty
        )
        #expect(
            try privateContent.consumeFunctionArgumentsDelta(
                outputIndex: 0,
                itemID: "fc_private",
                callID: "call",
                name: "web_search",
                delta: "{}"
            ).isEmpty
        )
        #expect(
            try privateContent.consumeFunctionArgumentsDone(
                outputIndex: 0,
                itemID: "fc_private",
                callID: "call",
                name: "web_search",
                arguments: "{}"
            ).isEmpty
        )

        var privateAdded = try coverageProviderSession()
        privateAdded.providerOutput[0] = coverageOutputMapping(
            id: "fc_private",
            type: "function_call",
            name: "web_search",
            callID: "call",
            publicIndex: nil,
            isPrivateSearch: true
        )
        #expect(
            try privateAdded.consumeContentPartAdded(
                outputIndex: 0,
                contentIndex: 0,
                itemID: "fc_private",
                partJSON: responseData(outputTextPart("private"))
            ).isEmpty
        )
    }
}

extension OpenAIPublicProviderEventCoverageTests {
    @Test("Passthrough validation rejects every malformed reference family")
    // This table keeps all supported passthrough families fail-closed.
    // swiftlint:disable:next function_body_length
    func passthroughEdges() throws {
        var inactive = try coverageProviderSession()
        inactive.providerTurnActive = false
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try inactive.consumePassthrough(
                type: "response.content_part.done",
                payloadJSON: responseData(["type": "response.content_part.done"])
            )
        }

        var mismatchedType = try coverageProviderSession()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try mismatchedType.consumePassthrough(
                type: "response.content_part.done",
                payloadJSON: responseData(["type": "other"])
            )
        }

        var missingIndex = try coverageProviderSession()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingIndex.consumePassthrough(
                type: "response.content_part.done",
                payloadJSON: responseData([
                    "type": "response.content_part.done",
                    "item_id": "msg",
                ])
            )
        }

        var invalidIndex = try coverageProviderSession()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try invalidIndex.consumePassthrough(
                type: "response.content_part.done",
                payloadJSON: responseData([
                    "type": "response.content_part.done",
                    "output_index": -1,
                    "item_id": "msg",
                ])
            )
        }

        var wrongItem = try coverageProviderSession()
        wrongItem.providerOutput[0] = coverageOutputMapping(id: "msg", type: "message")
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try wrongItem.consumePassthrough(
                type: "response.content_part.done",
                payloadJSON: responseData([
                    "type": "response.content_part.done",
                    "output_index": 0,
                    "item_id": "other",
                ])
            )
        }

        var missingContent = try coverageProviderSession()
        missingContent.providerOutput[0] = coverageOutputMapping(id: "msg", type: "message")
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingContent.consumePassthrough(
                type: "response.content_part.done",
                payloadJSON: responseData([
                    "type": "response.content_part.done",
                    "output_index": 0,
                    "content_index": 0,
                    "item_id": "msg",
                    "part": outputTextPart(""),
                ])
            )
        }

        var invalidAnnotation = try coverageProviderSession()
        var message = coverageOutputMapping(id: "msg", type: "message")
        message.content[0] = .init(publicIndex: 0, type: "refusal")
        invalidAnnotation.providerOutput[0] = message
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try invalidAnnotation.consumePassthrough(
                type: "response.output_text.annotation.added",
                payloadJSON: responseData([
                    "type": "response.output_text.annotation.added",
                    "output_index": 0,
                    "content_index": 0,
                    "item_id": "msg",
                    "annotation_index": 0,
                    "annotation": ["type": "file_path", "file_id": "f", "index": 0],
                ])
            )
        }

        var mismatchedDonePart = try coverageProviderSession()
        var mismatchedDoneMessage = coverageOutputMapping(id: "msg", type: "message")
        mismatchedDoneMessage.content[0] = .init(publicIndex: 0, type: "output_text")
        mismatchedDonePart.providerOutput[0] = mismatchedDoneMessage
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try mismatchedDonePart.consumePassthrough(
                type: "response.content_part.done",
                payloadJSON: responseData([
                    "type": "response.content_part.done",
                    "output_index": 0,
                    "content_index": 0,
                    "item_id": "msg",
                    "part": ["type": "refusal", "refusal": "No"],
                ])
            )
        }

        var wrongContentHelper = try coverageProviderSession()
        var contentMapping = coverageOutputMapping(id: "msg", type: "message")
        contentMapping.content[0] = .init(publicIndex: 0, type: "output_text")
        wrongContentHelper.providerOutput[0] = contentMapping
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try wrongContentHelper.consumePassthrough(
                type: "response.reasoning_summary_text.delta",
                payloadJSON: responseData([
                    "type": "response.reasoning_summary_text.delta",
                    "output_index": 0,
                    "content_index": 0,
                    "item_id": "msg",
                    "summary_index": 0,
                    "delta": "x",
                ])
            )
        }

        var privateMappingSession = try coverageProviderSession()
        var privateMapping = coverageOutputMapping(
            id: "fc",
            type: "function_call",
            name: "web_search",
            callID: "call",
            publicIndex: nil,
            isPrivateSearch: true
        )
        privateMapping.content[0] = .init(publicIndex: 0, type: "output_text")
        privateMappingSession.providerOutput[0] = privateMapping
        #expect(
            try privateMappingSession.consumePassthrough(
                type: "response.output_text.annotation.added",
                payloadJSON: responseData([
                    "type": "response.output_text.annotation.added",
                    "output_index": 0,
                    "content_index": 0,
                    "item_id": "fc",
                    "annotation_index": 0,
                    "annotation": ["type": "file_path", "file_id": "f", "index": 0],
                ])
            ).isEmpty
        )
    }

    @Test("Reasoning passthrough and terminal validation reject malformed payloads")
    // The cases intentionally exercise every reasoning event payload branch.
    func reasoningAndTerminalEdges() throws {
        let badReasoningPayloads: [(String, [String: Any])] = [
            (
                "response.reasoning_summary_text.delta",
                ["summary_index": 0, "delta": 1]
            ),
            (
                "response.reasoning_summary_text.done",
                ["summary_index": 0, "text": 1]
            ),
            (
                "response.content_part.done",
                ["summary_index": 0, "part": outputTextPart("")]
            ),
        ]
        for (type, extra) in badReasoningPayloads {
            var session = try coverageProviderSession()
            session.providerOutput[0] = coverageOutputMapping(id: "rs", type: "reasoning")
            var payload: [String: Any] = [
                "type": type,
                "output_index": 0,
                "item_id": "rs",
            ]
            payload.merge(extra) { _, new in new }
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try session.consumePassthrough(type: type, payloadJSON: responseData(payload))
            }
        }

        var wrongReasoningOutput = try coverageProviderSession()
        wrongReasoningOutput.providerOutput[0] = coverageOutputMapping(id: "msg", type: "message")
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try wrongReasoningOutput.consumePassthrough(
                type: "response.reasoning_summary_text.delta",
                payloadJSON: responseData([
                    "type": "response.reasoning_summary_text.delta",
                    "output_index": 0,
                    "item_id": "msg",
                    "summary_index": 0,
                    "delta": "x",
                ])
            )
        }

        var activeOutput = try coverageProviderSession()
        activeOutput.providerOutput[0] = coverageOutputMapping(id: "msg", type: "message")
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try activeOutput.consumeProviderTerminal(
                status: .completed,
                responseJSON: responseData([:])
            )
        }

        var invalidFailure = try coverageProviderSession()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try invalidFailure.consumeProviderTerminal(
                status: .failed,
                responseJSON: responseData([
                    "id": "resp", "object": "response", "status": "failed",
                    "error": ["message": "no code"],
                ])
            )
        }

        var invalidCompleted = try coverageProviderSession()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try invalidCompleted.consumeProviderTerminal(
                status: .completed,
                responseJSON: responseData([
                    "id": "resp", "object": "response", "status": "completed",
                    "output": [], "usage": NSNull(),
                ])
            )
        }
    }
}

private func coverageProviderSession() throws -> ResponsesPublicStreamSession {
    var session = ResponsesPublicStreamSession(webSearch: try preparedWebSearchRequest())
    session.started = true
    session.providerTurnActive = true
    return session
}

private func coverageMessage(
    id: String,
    status: String = "in_progress"
) -> [String: Any] {
    [
        "id": id,
        "type": "message",
        "status": status,
        "role": "assistant",
        "content": [],
    ]
}

private func coverageOutputMapping(
    id: String,
    type: String,
    name: String? = nil,
    callID: String? = nil,
    publicIndex: Int? = 0,
    isPrivateSearch: Bool = false
) -> ResponsesPublicStreamSession.OutputMapping {
    .init(
        id: id,
        type: type,
        name: name,
        callID: callID,
        publicIndex: publicIndex,
        isPrivateSearch: isPrivateSearch
    )
}
