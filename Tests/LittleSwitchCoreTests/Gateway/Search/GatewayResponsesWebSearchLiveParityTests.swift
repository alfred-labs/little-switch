import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Gateway Responses web search live parity")
struct GatewayResponsesWebSearchLiveParityTests {
    @Test("Two searches and an ordinary final tool share one ordered Codex session")
    func twoSearchesAndOrdinaryTool() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture(maximumUses: 2)
        let final = responsesModelResponse(
            id: "resp_final_with_tool",
            output: [
                [
                    "id": "msg_final",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [outputTextPart("Done")],
                ],
                functionCallItem(
                    id: "fc_weather",
                    callID: "call_weather",
                    name: "weather",
                    arguments: #"{"city":"Paris"}"#,
                    status: "completed"
                ),
            ],
            inputTokens: 7,
            outputTokens: 4
        )
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: responsesSearchResponse(
                    id: "resp_search_one",
                    callID: "call_search_one",
                    query: "first"
                )
            ),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(
                status: .ok,
                body: responsesSearchResponse(
                    id: "resp_search_two",
                    callID: "call_search_two",
                    query: "second"
                )
            ),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(status: .ok, body: final),
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
        let events = try ResponsesStreamingTestSupport.events(
            try await responseBodyData(result.body)
        )

        #expect(events.map(\.sequenceNumber) == Array(0..<events.count).map(Optional.some))
        #expect(
            events.filter { $0.name == "response.web_search_call.searching" }.count
                == 2
        )
        #expect(
            events.filter { $0.name == "response.web_search_call.completed" }.count
                == 2
        )
        #expect(events.last?.name == "response.completed")
        let terminal = try #require(events.last?.payload["response"] as? [String: Any])
        let output = try #require(terminal["output"] as? [[String: Any]])
        #expect(
            output.compactMap { $0["type"] as? String }
                == ["web_search_call", "web_search_call", "message", "function_call"]
        )
        try #require(output.count == 4)
        try assertGatewayResponsesSearchItem(output[0], query: "first")
        try assertGatewayResponsesSearchItem(output[1], query: "second")
        let searchIDs = output.prefix(2).compactMap { $0["id"] as? String }
        #expect(Set(searchIDs).count == 2)
        #expect(
            searchIDs.allSatisfy { id in
                id.range(of: #"^ws_[a-z0-9_]+$"#, options: .regularExpression) != nil
            })
        #expect(output.last?["name"] as? String == "weather")

        let requests = await transport.requests
        #expect(requests.count == 5)
        #expect(requests.filter { $0.url.contains("firecrawl") }.count == 2)
    }

    @Test("The live maximum-use boundary marks the second search failed without Firecrawl")
    func maximumUses() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture(maximumUses: 3)
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: responsesSearchResponse(
                    id: "resp_search_one",
                    callID: "call_search_one",
                    query: "first"
                )
            ),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(
                status: .ok,
                body: responsesSearchResponse(
                    id: "resp_search_two",
                    callID: "call_search_two",
                    query: "second"
                )
            ),
            response(status: .ok, body: responsesFinalResponse("Limit reached")),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let result = try await responder.responsesWebSearchResponse(
            context: liveResponsesSearchContext(fixture: fixture, maxToolCalls: 1)
        )
        let events = try ResponsesStreamingTestSupport.events(
            try await responseBodyData(result.body)
        )
        #expect(
            events.filter { $0.name == "response.web_search_call.completed" }.count
                == 1
        )
        #expect(events.last?.name == "response.completed")
        let terminal = try #require(events.last?.payload["response"] as? [String: Any])
        let output = try #require(terminal["output"] as? [[String: Any]])
        try #require(output.count == 3)
        try assertGatewayResponsesSearchItem(output[0], query: "first")
        try assertGatewayResponsesSearchItem(output[1], query: "second", failed: true)
        let doneStatuses = events.compactMap { event -> String? in
            guard event.name == "response.output_item.done",
                let item = event.payload["item"] as? [String: Any],
                item["type"] as? String == "web_search_call"
            else { return nil }
            return item["status"] as? String
        }
        #expect(doneStatuses == ["completed", "failed"])

        let requests = await transport.requests
        #expect(requests.count == 4)
        #expect(requests.filter { $0.url.contains("firecrawl") }.count == 1)
        let finalRequest = try responsesGatewayObject(requests[3].body)
        let messages = try #require(finalRequest["messages"] as? [[String: Any]])
        #expect(messages.last?["content"] as? String == "max_uses_exceeded")
    }

}

extension GatewayResponsesWebSearchLiveParityTests {
    @Test("The first live provider failure stays transparent")
    func firstProviderFailure() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let privateBody = #"{"error":{"message":"provider-limit"}}"#
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                response(status: .tooManyRequests, body: privateBody)
            ]),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let result = try await responder.responsesWebSearchResponse(
            context: liveResponsesSearchContext(fixture: fixture)
        )
        #expect(result.status.code == 429)
        #expect(
            String(data: try await responseBodyData(result.body), encoding: .utf8)
                == privateBody
        )
    }

    @Test("A no-search length finish produces response.incomplete")
    func incompleteFinalTurn() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let providerBody =
            #"""
            {
              "id": "chatcmpl_length",
              "object": "chat.completion",
              "created": 200,
              "model": "glm-5.2",
              "choices": [{
                "index": 0,
                "finish_reason": "length",
                "message": {"role": "assistant", "content": "partial"}
              }],
              "usage": {"prompt_tokens": 3, "completion_tokens": 2, "total_tokens": 5}
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
        let events = try ResponsesStreamingTestSupport.events(
            try await responseBodyData(result.body)
        )
        #expect(events.last?.name == "response.incomplete")
        #expect(!events.contains { $0.name == "response.completed" })
        let terminal = try #require(events.last?.payload["response"] as? [String: Any])
        #expect(terminal["status"] as? String == "incomplete")
        #expect(
            (terminal["incomplete_details"] as? [String: Any])?["reason"] as? String
                == "max_output_tokens"
        )
    }

    @Test("An empty live query skips Firecrawl and still closes the search item")
    func emptyQuery() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: responsesSearchResponse(
                    id: "resp_empty",
                    callID: "call_empty",
                    query: "  "
                )
            ),
            response(status: .ok, body: responsesFinalResponse("Invalid query")),
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
        let events = try ResponsesStreamingTestSupport.events(
            try await responseBodyData(result.body)
        )
        #expect(!events.contains { $0.name == "response.web_search_call.completed" })
        #expect(events.last?.name == "response.completed")
        let terminal = try #require(events.last?.payload["response"] as? [String: Any])
        let output = try #require(terminal["output"] as? [[String: Any]])
        try assertGatewayResponsesSearchItem(#require(output.first), query: "  ", failed: true)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { !$0.url.contains("firecrawl") })
        let finalRequest = try responsesGatewayObject(requests[1].body)
        let messages = try #require(finalRequest["messages"] as? [[String: Any]])
        #expect(messages.last?["content"] as? String == "invalid_request")
    }

    @Test("A live Firecrawl failure is private and forces one final model turn")
    func firecrawlFailure() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: responsesSearchResponse(
                    id: "resp_search",
                    callID: "call_search",
                    query: "Swift"
                )
            ),
            response(status: .tooManyRequests, body: #"{"private":"firecrawl body"}"#),
            response(status: .ok, body: responsesFinalResponse("Unavailable")),
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
        let body = try await responseBodyData(result.body)
        let events = try ResponsesStreamingTestSupport.events(body)
        #expect(events.last?.name == "response.completed")
        #expect(!events.contains { $0.name == "error" })
        #expect(!events.contains { $0.name == "response.web_search_call.completed" })
        let terminal = try #require(events.last?.payload["response"] as? [String: Any])
        let output = try #require(terminal["output"] as? [[String: Any]])
        try assertGatewayResponsesSearchItem(#require(output.first), query: "Swift", failed: true)
        #expect(String(data: body, encoding: .utf8)?.contains("firecrawl body") == false)
        let requests = await transport.requests
        try #require(requests.count == 3)
        let finalRequest = try responsesGatewayObject(requests[2].body)
        let messages = try #require(finalRequest["messages"] as? [[String: Any]])
        #expect(messages.last?["content"] as? String == "unavailable")
    }

    @Test("Cancellation during live Firecrawl emits no protocol error")
    func firecrawlCancellation() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let transport = SteppingGatewayTransport(steps: [
            .response(
                liveResponsesStreamingResponse(
                    DemandTrackedBodySequence(
                        chunks: [try responsesGatewaySSE(liveNativeSearchFrames())]
                    )
                )
            ),
            .cancellation,
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
        let stages = StreamingStageRecorder()
        let body = result.body

        await #expect(throws: CancellationError.self) {
            try await body.write(ObservingResponseBodyWriter(recorder: stages))
        }
        let stream = await stages.bodyString
        #expect(stream.contains("event: response.web_search_call.searching\n"))
        #expect(!stream.contains("event: error\n"))
        #expect(!stream.contains("event: response.failed\n"))
        #expect(await stages.finishCount == 0)
    }
}
