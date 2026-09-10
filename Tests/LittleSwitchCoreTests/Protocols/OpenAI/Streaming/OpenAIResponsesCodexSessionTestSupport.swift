import Foundation
import Testing

@testable import LittleSwitchCore

func startCodexSearchSession(
    _ session: inout ResponsesPublicStreamSession
) throws -> [Data] {
    let frames = try session.start(
        responseJSON: responseData(
            responseObject(
                id: "resp_public",
                createdAt: 60,
                status: "in_progress",
                output: [],
                usage: nil
            )
        )
    )
    let privateStart = functionCallItem(
        id: "fc_private_provider",
        callID: "call_private_provider",
        name: "web_search",
        arguments: "",
        status: "in_progress"
    )
    let privateDone = functionCallItem(
        id: "fc_private_provider",
        callID: "call_private_provider",
        name: "web_search",
        arguments: #"{"query":"latest Swift"}"#,
        status: "completed"
    )
    let suppressed: [ResponsesProviderStreamEvent] = [
        .outputItemAdded(outputIndex: 900, itemJSON: try responseData(privateStart)),
        .functionArgumentsDelta(
            outputIndex: 900,
            itemID: "fc_private_provider",
            callID: "call_private_provider",
            name: "web_search",
            delta: #"{"query":"latest "#
        ),
        .functionArgumentsDone(
            outputIndex: 900,
            itemID: "fc_private_provider",
            callID: "call_private_provider",
            name: "web_search",
            arguments: #"{"query":"latest Swift"}"#
        ),
        .outputItemDone(outputIndex: 900, itemJSON: try responseData(privateDone)),
        .terminal(
            status: .completed,
            responseJSON: try responseData(
                responseObject(
                    id: "resp_private_provider",
                    createdAt: 60,
                    status: "completed",
                    output: [privateDone],
                    usage: .init(inputTokens: 2, outputTokens: 1)
                )
            )
        ),
    ]
    for event in suppressed {
        #expect(try session.consumePublic(event).isEmpty)
    }
    return frames
}

func expectCodexSearchFixture(_ frames: [Data]) throws {
    let events = try publicEvents(frames)
    let searchEvents = events.filter {
        $0.name == "response.output_item.added"
            || $0.name.hasPrefix("response.web_search_call.")
            || $0.name == "response.output_item.done"
    }
    #expect(
        searchEvents.map(\.name) == [
            "response.output_item.added",
            "response.web_search_call.in_progress",
            "response.web_search_call.searching",
            "response.web_search_call.completed",
            "response.output_item.done",
        ]
    )

    let added = try #require(searchEvents[0].payload["item"] as? [String: Any])
    #expect(
        NSDictionary(dictionary: added).isEqual(to: [
            "type": "web_search_call",
            "id": "ws_public",
            "status": "in_progress",
        ])
    )
    #expect(added["action"] == nil)
    for event in searchEvents[1...3] {
        #expect(
            Set(event.payload.keys)
                == ["type", "sequence_number", "item_id", "output_index"]
        )
        #expect(event.payload["item_id"] as? String == "ws_public")
        #expect(event.payload["output_index"] as? Int == 0)
    }

    let done = try #require(searchEvents[4].payload["item"] as? [String: Any])
    #expect(
        NSDictionary(dictionary: done).isEqual(to: [
            "type": "web_search_call",
            "id": "ws_public",
            "status": "completed",
            "action": ["type": "search", "query": "latest Swift"],
        ])
    )
    #expect(searchEvents[4].payload["output_index"] as? Int == 0)
    #expect(searchEvents.dropFirst().dropLast().allSatisfy { $0.name != "response.output_item.added" })
    let stream = try #require(String(bytes: frames.joined(), encoding: .utf8))
    #expect(!stream.contains("fc_private_provider"))
    #expect(!stream.contains("call_private_provider"))
}
