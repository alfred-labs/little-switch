import Foundation
import NIOCore
import Testing

@testable import LittleSwitchCore

/// A native Responses SSE body that stops before a terminal event is an
/// upstream disconnection mid-turn: the client stream must end with a named
/// failure, not the blanket "Internal server error" that hid the cause.
@Suite("Gateway Responses upstream disconnection")
struct GatewayUpstreamDisconnectionTests {
    @Test("Truncated native Responses stream names the upstream disconnection")
    func nativeTruncatedStreamReportsUpstreamEnded() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(
                responses: [
                    liveResponsesStreamingResponse(
                        DemandTrackedBodySequence(
                            chunks: [
                                try responsesGatewaySSE([
                                    createdFrame(id: "resp_truncated_live", createdAt: 96),
                                    responsesFrame(
                                        "response.output_item.added",
                                        [
                                            "output_index": 0,
                                            "item": [
                                                "id": "msg_truncated_live",
                                                "type": "message",
                                                "status": "in_progress",
                                                "role": "assistant",
                                                "content": [],
                                            ] as [String: Any],
                                        ]
                                    ),
                                ])
                            ]
                        )
                    )
                ]
            ),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let result = try await responder.responsesWebSearchResponse(
            context: liveResponsesSearchContext(fixture: fixture, native: true)
        )
        let recorder = StreamingStageRecorder()
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await result.body.write(ObservingResponseBodyWriter(recorder: recorder))
        }

        let body = await recorder.body
        let events = try ResponsesStreamingTestSupport.events(body)
        #expect(
            events.map(\.name)
                == [
                    "response.created", "response.in_progress", "response.output_item.added",
                    "error", "response.failed",
                ]
        )
        try #require(events.count == 5)
        #expect(
            events[3].payload["code"] as? String == "server_error"
        )
        #expect(
            events[3].payload["message"] as? String
                == ResponsesPublicStreamSession.FailureWording
                .upstreamEndedBeforeCompletion.text
        )
        let failed = try #require(events[4].payload["response"] as? [String: Any])
        #expect(
            (failed["error"] as? [String: String])?["message"]
                == ResponsesPublicStreamSession.FailureWording
                .upstreamEndedBeforeCompletion.text
        )
    }
}

extension GatewayUpstreamDisconnectionTests {
    /// Replays the significant frames of a fresh failed native burst
    /// end-to-end. Before the sanitizer null fix they died as
    /// invalidProviderStream("invalidResponse") — vLLM stamps reasoning
    /// items with "content": null. Now they relay, and the stream (cut mid-
    /// recording at the production throw) ends as the named upstream
    /// disconnection instead of the blanket Internal server error. The
    /// recorded created/in_progress frames carry a 600 KB tools echo;
    /// minimal equivalents stand in for them.
    @Test("Recorded native burst relays and names its upstream end")
    func recordedNativeBurstRelays() async throws {
        let frames = try [
            createdFrame(id: "resp_8e7127ad45508938", createdAt: 1_788_523_676),
            responsesFrame("response.in_progress", [String: Any]()),
            responsesFrame(
                "response.output_item.added",
                [
                    "output_index": 0,
                    "item": [
                        "id": "83a009f8dee2cc6d",
                        "summary": [] as [[String: Any]],
                        "type": "reasoning",
                        "content": NSNull(),
                        "encrypted_content": NSNull(),
                        "status": "in_progress",
                    ] as [String: Any],
                ]
            ),
            responsesFrame(
                "response.reasoning_part.added",
                [
                    "content_index": 0,
                    "item_id": "83a009f8dee2cc6d",
                    "output_index": 0,
                    "part": ["text": "", "type": "reasoning_text"],
                ]
            ),
            responsesFrame(
                "response.reasoning_text.delta",
                [
                    "content_index": 0, "delta": "The user",
                    "item_id": "83a009f8dee2cc6d", "output_index": 0,
                ]
            ),
            responsesFrame(
                "response.reasoning_text.delta",
                [
                    "content_index": 0, "delta": " saying \"",
                    "item_id": "83a009f8dee2cc6d", "output_index": 0,
                ]
            ),
        ]
        let body = try responsesGatewaySSE(frames)
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(
                responses: [
                    liveResponsesStreamingResponse(
                        DemandTrackedBodySequence(chunks: [body])
                    )
                ]
            ),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let result = try await responder.responsesWebSearchResponse(
            context: liveResponsesSearchContext(fixture: fixture, native: true)
        )
        let recorder = StreamingStageRecorder()
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await result.body.write(ObservingResponseBodyWriter(recorder: recorder))
        }

        let relayed = await recorder.body
        let events = try ResponsesStreamingTestSupport.events(relayed)
        let errorEvent = try #require(events.first { $0.name == "error" })
        #expect(
            errorEvent.payload["message"] as? String
                == ResponsesPublicStreamSession.FailureWording
                .upstreamEndedBeforeCompletion.text
        )
    }
}
