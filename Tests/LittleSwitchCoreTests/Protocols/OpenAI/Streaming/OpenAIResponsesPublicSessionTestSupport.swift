import Foundation
import Testing

@testable import LittleSwitchCore

func startPublicRemappingSession(
    _ session: inout ResponsesPublicStreamSession
) throws -> [Data] {
    var frames = try session.start(
        responseJSON: responseData(
            responseObject(
                id: "resp_public_stable",
                createdAt: 70,
                status: "in_progress",
                output: [],
                usage: nil
            )
        )
    )
    frames += try feedPublicMessageTurn(&session)
    return frames
}

func feedPublicMessageTurn(
    _ session: inout ResponsesPublicStreamSession
) throws -> [Data] {
    let messageStart: [String: Any] = [
        "id": "msg_public",
        "type": "message",
        "status": "in_progress",
        "role": "assistant",
        "content": [],
    ]
    let messageDone: [String: Any] = [
        "id": "msg_public",
        "type": "message",
        "status": "completed",
        "role": "assistant",
        "content": [outputTextPart("FIRST answer")],
    ]
    let events: [ResponsesProviderStreamEvent] = try [
        .outputItemAdded(outputIndex: 44, itemJSON: responseData(messageStart)),
        .contentPartAdded(
            outputIndex: 44,
            contentIndex: 12,
            itemID: "msg_public",
            partJSON: responseData(outputTextPart(""))
        ),
        .outputTextDelta(
            outputIndex: 44,
            contentIndex: 12,
            itemID: "msg_public",
            delta: "FIRST"
        ),
        .outputTextDone(
            outputIndex: 44,
            contentIndex: 12,
            itemID: "msg_public",
            text: "FIRST answer"
        ),
        .passthrough(
            type: "response.content_part.done",
            payloadJSON: responseData([
                "type": "response.content_part.done",
                "sequence_number": 8_888,
                "output_index": 44,
                "content_index": 12,
                "item_id": "msg_public",
                "part": outputTextPart("FIRST answer"),
            ])
        ),
        .outputItemDone(outputIndex: 44, itemJSON: responseData(messageDone)),
        .terminal(
            status: .completed,
            responseJSON: responseData(
                responseObject(
                    id: "resp_provider_first",
                    createdAt: 71,
                    status: "completed",
                    output: [messageDone],
                    usage: .init(inputTokens: 1, outputTokens: 2)
                )
            )
        ),
    ]
    return try events.flatMap { try session.consumePublic($0) }
}

func completePublicFunctionTurn(
    _ session: inout ResponsesPublicStreamSession
) throws -> [Data] {
    let functionStart = functionCallItem(
        id: "fc_public",
        callID: "call_public",
        name: "read_file",
        arguments: "",
        status: "in_progress"
    )
    let functionDone = functionCallItem(
        id: "fc_public",
        callID: "call_public",
        name: "read_file",
        arguments: #"{"path":"README.md"}"#,
        status: "completed"
    )
    let terminal = responseObject(
        id: "resp_provider_second",
        createdAt: 72,
        status: "incomplete",
        output: [functionDone],
        usage: .init(inputTokens: 2, outputTokens: 3)
    )
    let events: [ResponsesProviderStreamEvent] = try [
        .responseStarted(
            responseJSON: responseData(
                responseObject(
                    id: "resp_provider_second",
                    createdAt: 72,
                    status: "in_progress",
                    output: [],
                    usage: nil
                )
            )
        ),
        .outputItemAdded(outputIndex: 2, itemJSON: responseData(functionStart)),
        .functionArgumentsDelta(
            outputIndex: 2,
            itemID: "fc_public",
            callID: "call_public",
            name: "read_file",
            delta: #"{"path":"README"#
        ),
        .functionArgumentsDone(
            outputIndex: 2,
            itemID: "fc_public",
            callID: "call_public",
            name: "read_file",
            arguments: #"{"path":"README.md"}"#
        ),
        .outputItemDone(outputIndex: 2, itemJSON: responseData(functionDone)),
        .terminal(status: .incomplete, responseJSON: responseData(terminal)),
    ]
    var frames = try events.flatMap { try session.consumePublic($0) }
    frames += try session.finish(
        responseJSON: responseData(terminal),
        usage: ResponsesUsage(inputTokens: 9, outputTokens: 10)
    )
    return frames
}

func expectPublicRemapping(_ frames: [Data]) throws {
    let events = try publicEvents(frames)
    #expect(events.map(\.sequenceNumber) == Array(0..<events.count))
    #expect(events.first?.name == "response.created")
    #expect(events.dropFirst().first?.name == "response.in_progress")
    #expect(events.last?.name == "response.incomplete")
    #expect(!events.contains { $0.name == "response.completed" })

    let contentEvents = events.filter {
        $0.payload["item_id"] as? String == "msg_public"
            && $0.payload["content_index"] != nil
    }
    #expect(contentEvents.compactMap { $0.payload["output_index"] as? Int }.allSatisfy { $0 == 0 })
    #expect(contentEvents.compactMap { $0.payload["content_index"] as? Int }.allSatisfy { $0 == 0 })
    let stream = try #require(String(bytes: frames.joined(), encoding: .utf8))
    #expect(!stream.contains("8888"))

    let delta = try #require(
        events.first { $0.name == "response.function_call_arguments.delta" }
    )
    #expect(
        strippedEnvelope(delta.payload) as NSDictionary
            == [
                "item_id": "fc_public",
                "output_index": 1,
                "delta": #"{"path":"README"#,
            ] as NSDictionary
    )
    let done = try #require(
        events.first { $0.name == "response.function_call_arguments.done" }
    )
    #expect(
        strippedEnvelope(done.payload) as NSDictionary
            == [
                "item_id": "fc_public",
                "output_index": 1,
                "name": "read_file",
                "arguments": #"{"path":"README.md"}"#,
            ] as NSDictionary
    )

    let terminal = try #require(events.last?.payload["response"] as? [String: Any])
    #expect(terminal["id"] as? String == "resp_public_stable")
    #expect(terminal["created_at"] as? Int == 70)
    #expect(terminal["status"] as? String == "incomplete")
    #expect(terminal["model"] as? String == "little-switch-route")
    let tools = try #require(terminal["tools"] as? [[String: Any]])
    #expect(tools.compactMap { $0["type"] as? String } == ["web_search", "function"])
    let output = try #require(terminal["output"] as? [[String: Any]])
    #expect(output.compactMap { $0["id"] as? String } == ["msg_public", "fc_public"])
    #expect(output.allSatisfy { $0["name"] as? String != "web_search" })
    let usage = try #require(terminal["usage"] as? [String: Any])
    #expect(
        NSDictionary(dictionary: usage).isEqual(to: [
            "input_tokens": 9,
            "input_tokens_details": [
                "cached_tokens": 0,
                "cache_write_tokens": 0,
            ],
            "output_tokens": 10,
            "output_tokens_details": ["reasoning_tokens": 0],
            "total_tokens": 19,
        ])
    )
}

func publicEventObject(
    _ key: String,
    event name: String,
    in events: [PublicResponseEvent]
) throws -> [String: Any] {
    try #require(events.first { $0.name == name }?.payload[key] as? [String: Any])
}

func expectDefaultResponsesUsage(
    _ value: Any?,
    _ inputTokens: Int,
    _ outputTokens: Int,
    _ totalTokens: Int
) throws {
    let usage = try #require(value as? [String: Any])
    #expect(
        NSDictionary(dictionary: usage).isEqual(to: [
            "input_tokens": inputTokens,
            "input_tokens_details": [
                "cached_tokens": 0,
                "cache_write_tokens": 0,
            ],
            "output_tokens": outputTokens,
            "output_tokens_details": ["reasoning_tokens": 0],
            "total_tokens": totalTokens,
        ])
    )
}
