import Foundation
import Testing

@testable import LittleSwitchCore

// Ordered protocol fixtures are intentionally kept with their public-session assertions.
// swiftlint:disable file_length

extension OpenAIResponsesTurnStreamingTests {
    @Test("Public session remaps indices and keeps ordinary function deltas correct")
    func publicRemappingAndTerminal() throws {
        let prepared = try preparedWebSearchRequest()
        var session = ResponsesPublicStreamSession(webSearch: prepared)
        var frames = try startPublicRemappingSession(&session)
        frames += try completePublicFunctionTurn(&session)
        try expectPublicRemapping(frames)
    }

    @Test("Failure is safe, last, and terminal exactly once")
    func publicFailureTerminal() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: Data(
                #"{"model":"little-switch-chat","input":"Hello","stream":true}"#.utf8
            ),
            targetModel: "glm-5"
        )
        var session = ResponsesPublicStreamSession(chatCompletions: prepared)
        var frames = try session.start(
            responseJSON: responseData(
                responseObject(
                    id: "resp_chat_public",
                    createdAt: 80,
                    status: "in_progress",
                    output: [],
                    usage: nil
                )
            )
        )
        frames += try session.fail(message: "secret provider response body")

        let events = try publicEvents(frames)
        #expect(
            events.map(\.name) == [
                "response.created",
                "response.in_progress",
                "error",
                "response.failed",
            ])
        #expect(events.map(\.sequenceNumber) == [0, 1, 2, 3])
        #expect(events.last?.name == "response.failed")
        let error = try #require(events.first { $0.name == "error" })
        #expect(
            Set(error.payload.keys)
                == ["type", "sequence_number", "code", "message", "param"]
        )
        #expect(error.payload["code"] as? String == "server_error")
        #expect(error.payload["message"] as? String == "Internal server error")
        #expect(error.payload["param"] is NSNull)
        let stream = try #require(String(bytes: frames.joined(), encoding: .utf8))
        #expect(!stream.contains("secret"))
        let failed = try #require(events.last?.payload["response"] as? [String: Any])
        #expect(failed["id"] as? String == "resp_chat_public")
        #expect(failed["status"] as? String == "failed")
        #expect(failed["model"] as? String == "little-switch-chat")

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.fail(message: "again")
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.finish(
                responseJSON: responseData(failed),
                usage: .init(inputTokens: 0, outputTokens: 0)
            )
        }
    }

    @Test("Failure before response.created emits a safe native terminal lifecycle")
    func publicFailureBeforeStart() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: Data(
                #"{"model":"little-switch-chat","input":"Hello","stream":true}"#.utf8
            ),
            targetModel: "glm-5"
        )
        var session = ResponsesPublicStreamSession(chatCompletions: prepared)
        let frames = try session.fail(message: "secret provider response body")

        let events = try publicEvents(frames)
        #expect(events.map(\.name) == ["error", "response.failed"])
        #expect(events.map(\.sequenceNumber) == [0, 1])

        let error = events[0]
        #expect(
            Set(error.payload.keys)
                == ["type", "sequence_number", "code", "message", "param"]
        )
        #expect(error.payload["code"] as? String == "server_error")
        #expect(error.payload["message"] as? String == "Internal server error")
        #expect(error.payload["param"] is NSNull)

        let failed = try #require(events[1].payload["response"] as? [String: Any])
        let bridgeID = try #require(failed["id"] as? String)
        #expect(bridgeID.hasPrefix("resp_"))
        #expect(!bridgeID.contains("secret"))
        #expect((failed["created_at"] as? Int) ?? -1 >= 0)
        #expect(failed["object"] as? String == "response")
        #expect(failed["status"] as? String == "failed")
        #expect(failed["model"] as? String == "little-switch-chat")
        #expect((failed["output"] as? [Any])?.isEmpty == true)
        #expect(failed["usage"] is NSNull)
        #expect(
            failed["error"] as? [String: String]
                == [
                    "code": "server_error",
                    "message": "Internal server error",
                ]
        )
        let stream = try #require(String(bytes: frames.joined(), encoding: .utf8))
        #expect(!stream.contains("secret"))

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.fail(message: "again")
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.start(responseJSON: responseData(failed))
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.finish(
                responseJSON: responseData(failed),
                usage: .init(inputTokens: 0, outputTokens: 0)
            )
        }
    }

    @Test("A provider failure with no error payload is named, never echoed")
    func publicFailureWithoutProviderPayload() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: Data(
                #"{"model":"little-switch-chat","input":"Hello","stream":true}"#.utf8
            ),
            targetModel: "glm-5"
        )
        var session = ResponsesPublicStreamSession(chatCompletions: prepared)
        let frames = try session.fail(
            message: "secret provider response body",
            wording: .withoutProviderPayload
        )

        let events = try publicEvents(frames)
        #expect(events.map(\.name) == ["error", "response.failed"])
        #expect(
            events[0].payload["message"] as? String
                == ResponsesPublicStreamSession.FailureWording.withoutProviderPayload.text
        )
        let failed = try #require(events[1].payload["response"] as? [String: Any])
        #expect(
            failed["error"] as? [String: String]
                == [
                    "code": "server_error",
                    "message": ResponsesPublicStreamSession.FailureWording
                        .withoutProviderPayload.text,
                ]
        )
        let stream = try #require(String(bytes: frames.joined(), encoding: .utf8))
        #expect(!stream.contains("secret"))
    }

    @Test("Public passthrough keeps supported families and drops provider-only events")
    func publicPassthroughAllowlist() throws {
        let prepared = try preparedWebSearchRequest()
        var session = ResponsesPublicStreamSession(webSearch: prepared)
        var frames = try session.start(
            responseJSON: responseData(
                responseObject(
                    id: "resp_public_allowlist",
                    createdAt: 93,
                    status: "in_progress",
                    output: [],
                    usage: nil
                )
            )
        )

        let reasoningDone: [String: Any] = [
            "id": "rs_public",
            "type": "reasoning",
            "summary": [["type": "summary_text", "text": "Need a source"]],
        ]
        frames += try consumePublicReasoningEvents(session: &session)
        frames += try session.consumePublic(
            .passthrough(
                type: "response.provider_private.lifecycle",
                payloadJSON: responseData([
                    "type": "response.provider_private.lifecycle",
                    "provider_response_id": "provider-secret-response-id",
                    "message": "provider-secret-message",
                ])
            )
        )
        frames += try session.consumePublic(
            .outputItemDone(outputIndex: 40, itemJSON: responseData(reasoningDone))
        )

        let messageDone: [String: Any] = [
            "id": "msg_public_allowlist",
            "type": "message",
            "status": "completed",
            "role": "assistant",
            "content": [outputTextPart("Answer")],
        ]
        frames += try consumePublicAnnotatedMessage(session: &session)
        frames += try session.consumePublic(
            .outputItemDone(outputIndex: 44, itemJSON: responseData(messageDone))
        )

        let terminal = responseObject(
            id: "resp_provider_allowlist",
            createdAt: 94,
            status: "completed",
            output: [reasoningDone, messageDone],
            usage: .init(inputTokens: 2, outputTokens: 3)
        )
        frames += try session.consumePublic(
            .terminal(status: .completed, responseJSON: responseData(terminal))
        )
        frames += try session.finish(
            responseJSON: responseData(terminal),
            usage: .init(inputTokens: 2, outputTokens: 3)
        )

        let events = try publicEvents(frames)
        #expect(events.map(\.sequenceNumber) == Array(events.indices))
        #expect(events.last?.name == "response.completed")
        #expect(
            events.contains { $0.name == "response.reasoning_summary_text.delta" }
        )
        let reasoningPart = try #require(
            events.first { $0.name == "response.reasoning_summary_part.added" }?
                .payload["part"] as? [String: String]
        )
        #expect(reasoningPart == ["type": "summary_text", "text": ""])
        let annotation = try #require(
            events.first { $0.name == "response.output_text.annotation.added" }
        )
        #expect(annotation.payload["output_index"] as? Int == 1)
        #expect(annotation.payload["content_index"] as? Int == 0)
        #expect(
            Set(annotation.payload.keys)
                == [
                    "type",
                    "sequence_number",
                    "output_index",
                    "content_index",
                    "item_id",
                    "annotation_index",
                    "annotation",
                ]
        )
        #expect(
            annotation.payload["annotation"] as? [String: AnyHashable]
                == [
                    "type": "url_citation",
                    "start_index": 0,
                    "end_index": 6,
                    "title": "Swift",
                    "url": "https://swift.org/",
                ]
        )
        #expect(
            !events.contains { $0.name == "response.provider_private.lifecycle" }
        )
        let stream = try #require(String(bytes: frames.joined(), encoding: .utf8))
        #expect(!stream.contains("provider-secret"))
    }

    @Test("Public session rebuilds provider shells and recursively sanitizes output")
    // The fixture deliberately exercises every nested public boundary in one ordered session.
    // swiftlint:disable:next function_body_length
    func publicResponsePrivacyBoundary() throws {
        let prepared = try privacyPreparedWebSearchRequest()
        var session = ResponsesPublicStreamSession(webSearch: prepared)
        var frames = try session.start(
            responseJSON: responseData(
                poisonedPublicResponse(
                    id: "resp_public_privacy",
                    createdAt: 101,
                    status: "in_progress",
                    output: [],
                    usage: nil
                )
            )
        )

        let addedItem: [String: Any] = [
            "id": "msg_public_privacy",
            "type": "message",
            "status": "in_progress",
            "role": "assistant",
            "phase": "commentary",
            "content": [],
            "internal_chat_message_metadata_passthrough": [
                "turn_id": "turn_public",
                "provider_secret": "provider-secret-item-metadata-added",
            ],
            "provider_secret": "provider-secret-item-added",
        ]
        let addedPart = poisonedOutputTextPart(text: "")
        let donePart = poisonedOutputTextPart(text: "Safe answer")
        var doneItem = addedItem
        doneItem["status"] = "completed"
        doneItem["content"] = [donePart]
        doneItem["provider_secret"] = "provider-secret-item-done"

        let providerEvents: [ResponsesProviderStreamEvent] = try [
            .outputItemAdded(outputIndex: 9, itemJSON: responseData(addedItem)),
            .contentPartAdded(
                outputIndex: 9,
                contentIndex: 4,
                itemID: "msg_public_privacy",
                partJSON: responseData(addedPart)
            ),
            .outputTextDelta(
                outputIndex: 9,
                contentIndex: 4,
                itemID: "msg_public_privacy",
                delta: "Safe answer"
            ),
            .outputTextDone(
                outputIndex: 9,
                contentIndex: 4,
                itemID: "msg_public_privacy",
                text: "Safe answer"
            ),
            .passthrough(
                type: "response.content_part.done",
                payloadJSON: responseData([
                    "type": "response.content_part.done",
                    "output_index": 9,
                    "content_index": 4,
                    "item_id": "msg_public_privacy",
                    "part": donePart,
                    "provider_secret": "provider-secret-part-envelope-done",
                ])
            ),
            .outputItemDone(outputIndex: 9, itemJSON: responseData(doneItem)),
        ]
        frames += try providerEvents.flatMap { try session.consumePublic($0) }

        let terminal = poisonedPublicResponse(
            id: "resp_provider_terminal",
            createdAt: 102,
            status: "completed",
            output: [doneItem],
            usage: .init(inputTokens: 3, outputTokens: 5)
        )
        frames += try session.consumePublic(
            .terminal(status: .completed, responseJSON: responseData(terminal))
        )
        frames += try session.finish(
            responseJSON: responseData(terminal),
            usage: .init(inputTokens: 3, outputTokens: 5)
        )

        let stream = try #require(String(bytes: frames.joined(), encoding: .utf8))
        #expect(!stream.contains("provider-secret"))
        let events = try publicEvents(frames)
        #expect(events.map(\.sequenceNumber) == Array(events.indices))

        for eventName in ["response.created", "response.in_progress"] {
            let response = try #require(
                events.first { $0.name == eventName }?.payload["response"] as? [String: Any]
            )
            try expectClientOwnedPublicShell(response, status: "in_progress")
        }

        let itemAdded = try publicEventObject(
            "item",
            event: "response.output_item.added",
            in: events
        )
        #expect(
            Set(itemAdded.keys)
                == [
                    "id",
                    "type",
                    "status",
                    "role",
                    "phase",
                    "content",
                    "internal_chat_message_metadata_passthrough",
                ]
        )
        #expect(
            itemAdded["internal_chat_message_metadata_passthrough"] as? [String: String]
                == ["turn_id": "turn_public"]
        )

        let partAdded = try publicEventObject(
            "part",
            event: "response.content_part.added",
            in: events
        )
        try expectSanitizedOutputTextPart(partAdded, text: "")
        let partDone = try publicEventObject(
            "part",
            event: "response.content_part.done",
            in: events
        )
        try expectSanitizedOutputTextPart(partDone, text: "Safe answer")

        let itemDone = try publicEventObject(
            "item",
            event: "response.output_item.done",
            in: events
        )
        let itemDoneContent = try #require(itemDone["content"] as? [[String: Any]])
        try expectSanitizedOutputTextPart(try #require(itemDoneContent.first), text: "Safe answer")

        let completed = try #require(events.last?.payload["response"] as? [String: Any])
        try expectClientOwnedPublicShell(completed, status: "completed")
        let completedOutput = try #require(completed["output"] as? [[String: Any]])
        let completedContent = try #require(completedOutput.first?["content"] as? [[String: Any]])
        try expectSanitizedOutputTextPart(
            try #require(completedContent.first),
            text: "Safe answer"
        )
    }

    @Test("Provider failure cannot replace the client-owned public shell")
    func publicFailurePrivacyBoundary() throws {
        let prepared = try privacyPreparedWebSearchRequest()
        var session = ResponsesPublicStreamSession(webSearch: prepared)
        var frames = try session.start(
            responseJSON: responseData(
                poisonedPublicResponse(
                    id: "resp_public_failure",
                    createdAt: 111,
                    status: "in_progress",
                    output: [],
                    usage: nil
                )
            )
        )
        var failed = poisonedPublicResponse(
            id: "resp_provider_failure",
            createdAt: 112,
            status: "failed",
            output: [],
            usage: nil
        )
        failed["error"] = [
            "code": "provider-secret-code",
            "message": "provider-secret-message",
            "provider_secret": "provider-secret-error",
        ]
        frames += try session.consumePublic(
            .terminal(status: .failed, responseJSON: responseData(failed))
        )

        let stream = try #require(String(bytes: frames.joined(), encoding: .utf8))
        #expect(!stream.contains("provider-secret"))
        let events = try publicEvents(frames)
        #expect(
            events.map(\.name) == [
                "response.created",
                "response.in_progress",
                "error",
                "response.failed",
            ])
        let response = try #require(events.last?.payload["response"] as? [String: Any])
        try expectClientOwnedPublicShell(response, status: "failed")
        #expect(
            response["error"] as? [String: String]
                == [
                    "code": "server_error",
                    "message": "Internal server error",
                ]
        )
    }
}

private func consumePublicReasoningEvents(
    session: inout ResponsesPublicStreamSession
) throws -> [Data] {
    let reasoningStart: [String: Any] = [
        "id": "rs_public",
        "type": "reasoning",
        "summary": [],
    ]
    var frames = try session.consumePublic(
        .outputItemAdded(outputIndex: 40, itemJSON: responseData(reasoningStart))
    )
    for event in try publicReasoningEvents() {
        frames += try session.consumePublic(event)
    }
    return frames
}

private func consumePublicAnnotatedMessage(
    session: inout ResponsesPublicStreamSession
) throws -> [Data] {
    let messageStart: [String: Any] = [
        "id": "msg_public_allowlist",
        "type": "message",
        "status": "in_progress",
        "role": "assistant",
        "content": [],
    ]
    let part = outputTextPart("Answer")
    var frames = try session.consumePublic(
        .outputItemAdded(outputIndex: 44, itemJSON: responseData(messageStart))
    )
    frames += try session.consumePublic(
        .contentPartAdded(
            outputIndex: 44,
            contentIndex: 12,
            itemID: "msg_public_allowlist",
            partJSON: responseData(outputTextPart(""))
        )
    )
    frames += try session.consumePublic(
        .outputTextDelta(
            outputIndex: 44,
            contentIndex: 12,
            itemID: "msg_public_allowlist",
            delta: "Answer"
        )
    )
    frames += try session.consumePublic(try publicAnnotationEvent())
    frames += try session.consumePublic(
        .outputTextDone(
            outputIndex: 44,
            contentIndex: 12,
            itemID: "msg_public_allowlist",
            text: "Answer"
        )
    )
    frames += try session.consumePublic(
        .passthrough(
            type: "response.content_part.done",
            payloadJSON: responseData([
                "type": "response.content_part.done",
                "output_index": 44,
                "content_index": 12,
                "item_id": "msg_public_allowlist",
                "part": part,
            ])
        )
    )
    return frames
}

private func publicReasoningEvents() throws -> [ResponsesProviderStreamEvent] {
    let reference: [String: Any] = [
        "output_index": 40,
        "item_id": "rs_public",
        "summary_index": 7,
    ]
    return try [
        .passthrough(
            type: "response.reasoning_summary_part.added",
            payloadJSON: responseData(
                reference.merging([
                    "type": "response.reasoning_summary_part.added",
                    "sequence_number": 8_001,
                    "part": [
                        "type": "summary_text",
                        "text": "",
                        "provider_secret": "provider-secret-reasoning-part",
                    ],
                    "provider_secret": "provider-secret-reasoning",
                ]) { _, new in new }
            )
        ),
        .passthrough(
            type: "response.reasoning_summary_text.delta",
            payloadJSON: responseData(
                reference.merging([
                    "type": "response.reasoning_summary_text.delta",
                    "delta": "Need a source",
                ]) { _, new in new }
            )
        ),
        .passthrough(
            type: "response.reasoning_summary_text.done",
            payloadJSON: responseData(
                reference.merging([
                    "type": "response.reasoning_summary_text.done",
                    "text": "Need a source",
                ]) { _, new in new }
            )
        ),
        .passthrough(
            type: "response.reasoning_summary_part.done",
            payloadJSON: responseData(
                reference.merging([
                    "type": "response.reasoning_summary_part.done",
                    "part": [
                        "type": "summary_text",
                        "text": "Need a source",
                        "provider_secret": "provider-secret-reasoning-part-done",
                    ],
                ]) { _, new in new }
            )
        ),
    ]
}

private func publicAnnotationEvent() throws -> ResponsesProviderStreamEvent {
    .passthrough(
        type: "response.output_text.annotation.added",
        payloadJSON: try responseData([
            "type": "response.output_text.annotation.added",
            "sequence_number": 8_002,
            "output_index": 44,
            "content_index": 12,
            "item_id": "msg_public_allowlist",
            "annotation_index": 9,
            "annotation": [
                "type": "url_citation",
                "start_index": 0,
                "end_index": 6,
                "title": "Swift",
                "url": "https://swift.org/",
                "provider_secret": "provider-secret-nested-annotation",
            ],
            "provider_secret": "provider-secret-annotation",
        ])
    )
}

private func privacyPreparedWebSearchRequest() throws -> PreparedResponsesWebSearchRequest {
    let body = try responseData([
        "model": "little-switch-route",
        "input": "latest Swift",
        "stream": true,
        "metadata": ["owner": "client"],
        "parallel_tool_calls": true,
        "tools": [
            ["type": "web_search"],
            [
                "type": "function",
                "name": "read_file",
                "parameters": ["type": "object"],
            ],
        ],
    ])
    return try #require(
        try OpenAIResponsesWebSearch.prepare(
            body: body,
            targetModel: "provider-model",
            configuration: .firecrawlCloud
        )
    )
}

private func poisonedPublicResponse(
    id: String,
    createdAt: Int,
    status: String,
    output: [[String: Any]],
    usage: ResponsesUsage?
) -> [String: Any] {
    var response = responseObject(
        id: id,
        createdAt: createdAt,
        status: status,
        output: output,
        usage: usage
    )
    response["metadata"] = [
        "owner": "provider",
        "provider_secret": "provider-secret-shell-metadata",
    ]
    response["parallel_tool_calls"] = false
    response["provider_secret"] = "provider-secret-shell"
    return response
}

private func poisonedOutputTextPart(text: String) -> [String: Any] {
    [
        "type": "output_text",
        "text": text,
        "annotations": [
            [
                "type": "url_citation",
                "start_index": 0,
                "end_index": 4,
                "title": "Safe",
                "url": "https://example.com/",
                "provider_secret": "provider-secret-annotation",
            ]
        ],
        "logprobs": [
            [
                "token": "Safe",
                "logprob": -0.25,
                "bytes": [83, 97, 102, 101],
                "provider_secret": "provider-secret-logprob",
            ]
        ],
        "provider_secret": "provider-secret-part",
    ]
}

private func expectClientOwnedPublicShell(
    _ response: [String: Any],
    status: String
) throws {
    #expect(response["status"] as? String == status)
    #expect(response["model"] as? String == "little-switch-route")
    #expect(response["parallel_tool_calls"] as? Bool == true)
    #expect(response["metadata"] as? [String: String] == ["owner": "client"])
    #expect(response["provider_secret"] == nil)
    let tools = try #require(response["tools"] as? [[String: Any]])
    #expect(tools.compactMap { $0["type"] as? String } == ["web_search", "function"])
}

private func expectSanitizedOutputTextPart(
    _ part: [String: Any],
    text: String
) throws {
    #expect(Set(part.keys) == ["type", "text", "annotations", "logprobs"])
    #expect(part["type"] as? String == "output_text")
    #expect(part["text"] as? String == text)
    let annotations = try #require(part["annotations"] as? [[String: Any]])
    #expect(
        Set(try #require(annotations.first).keys)
            == ["type", "start_index", "end_index", "title", "url"]
    )
    let logprobs = try #require(part["logprobs"] as? [[String: Any]])
    #expect(Set(try #require(logprobs.first).keys) == ["token", "logprob", "bytes"])
}
