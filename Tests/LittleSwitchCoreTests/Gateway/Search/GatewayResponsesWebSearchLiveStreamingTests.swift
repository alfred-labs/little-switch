import AsyncHTTPClient
import Foundation
import HTTPTypes
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Gateway Responses web search live streaming")
// Keep the implementation-plan filter stable for focused gateway runs.
// swiftlint:disable:next type_name
struct GatewayResponsesWebSearchLiveStreamingTests {
    @Test("Native Responses returns after the head and streams through the search barrier")
    func nativeTimingBackpressureAndCodexContract() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture(maximumUses: 2)
        let stages = StreamingStageRecorder(blockingMarker: #""delta":"FIRST""#)
        let searchBody = DemandTrackedBodySequence(
            chunks: [try responsesGatewaySSE(liveNativeSearchFrames())],
            recorder: stages
        )
        let firecrawlGate = GatewayExecutionGate()
        let finalBody = DemandTrackedBodySequence(
            chunks: try liveNativeFinalChunks(),
            gatedNextCall: 1
        )
        let transport = GatewayLiveTransport(steps: [
            .response(liveResponsesStreamingResponse(searchBody)),
            .gated(
                firecrawlGate,
                response(
                    status: .ok,
                    body:
                        #"{"success":true,"data":{"web":[{"title":"Swift.org","url":"https://swift.org/","description":"Current"}]}}"#
                )
            ),
            .response(liveResponsesStreamingResponse(finalBody)),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let context = try liveResponsesSearchContext(fixture: fixture, native: true)

        let responseTask = Task {
            let response = try await responder.responsesWebSearchResponse(context: context)
            await stages.responseReturned()
            return response
        }
        let firstStage = await stages.waitForFirstStage()
        #expect(firstStage == .responseReturned)
        guard firstStage == .responseReturned else {
            await firecrawlGate.release()
            await finalBody.releaseGate()
            _ = try? await responseTask.value
            return
        }

        let liveResponse = try await responseTask.value
        #expect(liveResponse.status == .ok)
        #expect(liveResponse.headers[.contentType] == "text/event-stream")
        #expect(liveResponse.body.contentLength == nil)
        #expect(await searchBody.nextCallCount == 0)
        let initialRequests = await transport.requests
        try #require(initialRequests.count == 1)
        #expect(try responsesGatewayObject(initialRequests[0].body)["stream"] as? Bool == true)

        let body = liveResponse.body
        let bodyTask = Task {
            try await body.write(ObservingResponseBodyWriter(recorder: stages))
        }

        try await firecrawlGate.waitUntilEntered()
        let searching = await stages.bodyString
        #expect(searching.contains("event: response.web_search_call.searching\n"))
        #expect(!searching.contains("event: response.web_search_call.completed\n"))
        #expect(!searching.contains("fc_private_search"))
        await firecrawlGate.release()

        await stages.waitUntilContains("event: response.web_search_call.completed\n")
        await stages.waitUntilContains(#""delta":"FIRST""#)
        #expect(await finalBody.nextCallCount == 1)
        #expect(!(await stages.bodyString).contains(#""delta":" SECOND""#))
        await stages.releaseBlockedWrite()
        await finalBody.waitForNextCallCount(2)
        #expect(!(await stages.bodyString).contains(#""delta":" SECOND""#))
        await finalBody.releaseGate()
        try await bodyTask.value

        let events = try ResponsesStreamingTestSupport.events(await stages.body)
        let requests = await transport.requests
        try assertNativeResponsesSearchContract(events: events, requests: requests)
    }

    @Test("Z.AI private tool chunks become native Codex search events")
    func zaiSearchChunks() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture(maximumUses: 2)
        let transport = GatewayLiveTransport(steps: [
            .response(
                liveResponsesStreamingResponse(
                    DemandTrackedBodySequence(chunks: try liveZAIPrivateSearchChunks())
                )
            ),
            .response(response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#)),
            .response(
                liveResponsesStreamingResponse(
                    DemandTrackedBodySequence(chunks: try liveZAIFinalChunks())
                )
            ),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let result = try await responder.responsesWebSearchResponse(
            context: liveResponsesSearchContext(fixture: fixture)
        )
        #expect(result.body.contentLength == nil)
        let body = try await responseBodyData(result.body)
        let events = try ResponsesStreamingTestSupport.events(body)

        #expect(events.first?.name == "response.created")
        #expect(events.last?.name == "response.completed")
        #expect(events.contains { $0.name == "response.web_search_call.searching" })
        #expect(
            events.contains { event in
                event.name == "response.output_text.delta"
                    && event.payload["delta"] as? String == "FIRST"
            }
        )
        let stream = try #require(String(data: body, encoding: .utf8))
        #expect(!stream.contains(#""name":"web_search""#))
        #expect(!stream.contains("fc_resp_chatcmpl_search"))

        let requests = await transport.requests
        try #require(requests.count == 3)
        for request in [requests[0], requests[2]] {
            #expect(request.url == "https://api.z.ai/api/coding/paas/v4/chat/completions")
            let object = try responsesGatewayObject(request.body)
            #expect(object["stream"] as? Bool == true)
            #expect(object["tool_stream"] as? Bool == true)
            #expect(
                (object["stream_options"] as? [String: Any])?["include_usage"] as? Bool
                    == true
            )
        }
    }

    @Test("Provider JSON fallback still uses one live public Responses session")
    func jsonFallback() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: responsesSearchResponse(
                    id: "resp_json_search",
                    callID: "call_json_search",
                    query: "Swift JSON"
                )
            ),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(status: .ok, body: responsesFinalResponse("JSON FINAL")),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let result = try await responder.responsesWebSearchResponse(
            context: liveResponsesSearchContext(fixture: fixture)
        )
        #expect(result.body.contentLength == nil)
        let body = try await responseBodyData(result.body)
        let events = try ResponsesStreamingTestSupport.events(body)
        #expect(events.first?.name == "response.created")
        #expect(events.last?.name == "response.completed")
        #expect(events.filter { $0.name == "response.created" }.count == 1)
        #expect(events.filter { $0.name == "response.completed" }.count == 1)
        #expect(String(data: body, encoding: .utf8)?.contains("JSON FINAL") == true)

        let requests = await transport.requests
        try #require(requests.count == 3)
        #expect(try responsesGatewayObject(requests[0].body)["stream"] as? Bool == true)
        #expect(try responsesGatewayObject(requests[2].body)["stream"] as? Bool == true)
    }

}

@Suite("Gateway Responses web search live errors")
struct GatewayResponsesLiveErrorTests {
    @Test("Configured Responses search limit rejects cumulative Chat frames safely")
    func cumulativeSearchChatStreamLimitIsSafe() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let frames = try simpleChatFrames(finishReason: "stop")
        let maximumErrorBytes = try minimumChatFrameWireLimit(frames)
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                liveResponsesStreamingResponse(
                    DemandTrackedBodySequence(chunks: chatSSEChunks(frames))
                )
            ]),
            secretStore: fixture.secrets,
            maximumErrorBytes: maximumErrorBytes,
            requiredAuthorityPort: nil
        )

        let result = try await responder.responsesWebSearchResponse(
            context: liveResponsesSearchContext(fixture: fixture)
        )
        let recorder = StreamingStageRecorder()
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await result.body.write(
                ObservingResponseBodyWriter(recorder: recorder)
            )
        }

        let events = try ResponsesStreamingTestSupport.events(await recorder.body)
        #expect(events.last?.name == "response.failed")
        #expect(!events.contains { $0.name == "response.completed" })
        #expect(await recorder.finishCount == 1)
    }

    @Test("A committed follow-up failure emits one safe Responses failure terminal")
    func committedFailure() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let transport = GatewayLiveTransport(steps: [
            .response(
                liveResponsesStreamingResponse(
                    DemandTrackedBodySequence(
                        chunks: [try responsesGatewaySSE(liveNativeSearchFrames())]
                    )
                )
            ),
            .response(response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#)),
            .response(response(status: .internalServerError, body: #"{"private":"body"}"#)),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let result = try await responder.responsesWebSearchResponse(
            context: liveResponsesSearchContext(fixture: fixture, native: true)
        )
        let recorder = StreamingStageRecorder()
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await result.body.write(
                ObservingResponseBodyWriter(recorder: recorder)
            )
        }
        let body = await recorder.body
        let events = try ResponsesStreamingTestSupport.events(body)

        #expect(events.filter { $0.name == "error" }.count == 1)
        #expect(events.filter { $0.name == "response.failed" }.count == 1)
        #expect(!events.contains { $0.name == "response.completed" })
        let stream = try #require(String(data: body, encoding: .utf8))
        #expect(!stream.contains("private"))
        #expect(!stream.contains(#""body""#))
    }

    @Test("Native Responses SSE context exhaustion keeps Codex's public error code")
    func nativeSSEContextLengthFailure() async throws {
        try await assertNativeFailedResponse(
            transportResponse: liveResponsesStreamingResponse(
                DemandTrackedBodySequence(
                    chunks: [
                        try responsesGatewaySSE(
                            nativeFailedFrames(code: "context_length_exceeded")
                        )
                    ]
                )
            ),
            expectedCode: "context_length_exceeded"
        )
    }

    @Test("Native Responses JSON context exhaustion keeps Codex's public error code")
    func nativeJSONContextLengthFailure() async throws {
        try await assertNativeFailedResponse(
            transportResponse: response(
                status: .ok,
                body: try nativeFailedJSON(code: "context_length_exceeded")
            ),
            expectedCode: "context_length_exceeded"
        )
    }

    @Test("Native Responses JSON sanitizes other provider failure details")
    func nativeJSONProviderFailureIsPrivate() async throws {
        try await assertNativeFailedResponse(
            transportResponse: response(
                status: .ok,
                body: try nativeFailedJSON(code: "provider-secret-code")
            ),
            expectedCode: "server_error"
        )
    }

    @Test("Z.AI context exhaustion keeps Codex's native error code")
    func zaiContextLengthFailure() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let providerFrames = try [
            chatChunkFrame(choices: [
                chatChoice(delta: ["role": "assistant", "content": ""])
            ]),
            chatChunkFrame(choices: [
                chatChoice(delta: [:], finishReason: "model_context_window_exceeded")
            ]),
        ]
        let transport = GatewayLiveTransport(steps: [
            .response(
                liveResponsesStreamingResponse(
                    DemandTrackedBodySequence(
                        chunks: [try responsesGatewaySSE(providerFrames)]
                    )
                )
            )
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let result = try await responder.responsesWebSearchResponse(
            context: liveResponsesSearchContext(fixture: fixture)
        )
        let recorder = StreamingStageRecorder()
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await result.body.write(
                ObservingResponseBodyWriter(recorder: recorder)
            )
        }
        let events = try ResponsesStreamingTestSupport.events(await recorder.body)
        let error = try #require(events.first { $0.name == "error" })
        #expect(error.payload["code"] as? String == "context_length_exceeded")
        let failed = try #require(events.first { $0.name == "response.failed" })
        let response = try #require(failed.payload["response"] as? [String: Any])
        #expect(
            (response["error"] as? [String: Any])?["code"] as? String
                == "context_length_exceeded"
        )
    }

    @Test("Z.AI JSON context exhaustion keeps Codex's native error code")
    func zaiJSONContextLengthFailure() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let providerBody =
            #"""
            {
              "id": "chatcmpl_context",
              "object": "chat.completion",
              "created": 200,
              "model": "glm-5.2",
              "choices": [{
                "index": 0,
                "finish_reason": "model_context_window_exceeded",
                "message": {"role": "assistant", "content": null}
              }],
              "usage": {"prompt_tokens": 3, "completion_tokens": 0, "total_tokens": 3}
            }
            """#
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                response(status: .ok, body: providerBody)
            ]),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let result = try await responder.responsesWebSearchResponse(
            context: liveResponsesSearchContext(fixture: fixture)
        )
        let recorder = StreamingStageRecorder()
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await result.body.write(
                ObservingResponseBodyWriter(recorder: recorder)
            )
        }
        let events = try ResponsesStreamingTestSupport.events(await recorder.body)
        let error = try #require(events.first { $0.name == "error" })
        #expect(error.payload["code"] as? String == "context_length_exceeded")
        let failed = try #require(events.first { $0.name == "response.failed" })
        let response = try #require(failed.payload["response"] as? [String: Any])
        #expect(
            (response["error"] as? [String: Any])?["code"] as? String
                == "context_length_exceeded"
        )
    }

    @Test("Responses Lite additional tools do not activate the hosted search bridge")
    func responsesLiteIsNotEligible() throws {
        let body = Data(
            #"{"model":"slug","input":"x","additional_tools":[{"type":"web_search"}]}"#.utf8
        )
        #expect(
            try OpenAIResponsesWebSearch.prepare(
                body: body,
                targetModel: "target",
                configuration: .firecrawlCloud
            ) == nil
        )
    }
}

private func assertNativeFailedResponse(
    transportResponse: HTTPClientResponse,
    expectedCode: String
) async throws {
    let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
    let responder = GatewayResponder(
        state: fixture.state,
        transport: RecordingGatewayTransport(responses: [transportResponse]),
        secretStore: fixture.secrets,
        requiredAuthorityPort: nil
    )
    let result = try await responder.responsesWebSearchResponse(
        context: liveResponsesSearchContext(fixture: fixture, native: true)
    )
    let recorder = StreamingStageRecorder()
    await #expect(throws: GatewayCommittedStreamFailure.self) {
        try await result.body.write(
            ObservingResponseBodyWriter(recorder: recorder)
        )
    }

    let body = await recorder.body
    let events = try ResponsesStreamingTestSupport.events(body)
    #expect(
        events.map(\.name)
            == ["response.created", "response.in_progress", "error", "response.failed"]
    )
    try #require(events.count == 4)
    #expect(events.map(\.sequenceNumber) == Array(events.indices).map(Optional.some))
    #expect(events[2].payload["code"] as? String == expectedCode)
    #expect(events[2].payload["message"] as? String == "Internal server error")
    let failed = try #require(events[3].payload["response"] as? [String: Any])
    #expect(
        failed["error"] as? [String: String]
            == [
                "code": expectedCode,
                "message": "Internal server error",
            ]
    )
    #expect((failed["output"] as? [Any])?.isEmpty == true)
    #expect(failed["usage"] is NSNull)
    let stream = try #require(String(data: body, encoding: .utf8))
    #expect(!stream.contains("provider-secret-message"))
    if expectedCode == "server_error" {
        #expect(!stream.contains("provider-secret-code"))
    }
}

private func nativeFailedFrames(code: String) throws -> [ServerSentEventFrame] {
    try [
        createdFrame(id: "resp_native_failed", createdAt: 95),
        responsesFrame(
            "error",
            [
                "code": code,
                "message": "provider-secret-error-event",
                "param": NSNull(),
            ]
        ),
        responsesFrame(
            "response.failed",
            [
                "response": try responsesGatewayObject(
                    Data(nativeFailedJSON(code: code).utf8)
                )
            ]
        ),
    ]
}
