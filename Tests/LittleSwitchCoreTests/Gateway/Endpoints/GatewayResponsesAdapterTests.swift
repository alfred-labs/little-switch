import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("z.ai Responses adapt Chat Completions back into a Responses stream")
    func responsesForwarding() async throws {
        let fixture = try makeFixture()
        // The save-time probe already learned z.ai has no native
        // /v1/responses route, so dispatch starts on the adapter.
        for provider in fixture.snapshot.providers where provider.name == "z.ai" {
            await fixture.state.responsesCapabilities.record(
                providerID: provider.id,
                supportsNative: false
            )
        }
        let chatResponse =
            #"""
            {
              "id": "chatcmpl_1",
              "created": 42,
              "choices": [
                {
                  "finish_reason": "stop",
                  "message": {"role": "assistant", "content": "OK"}
                }
              ],
              "usage": {"prompt_tokens": 2, "completion_tokens": 1, "total_tokens": 3}
            }
            """#
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: chatResponse)
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let mapping = try #require(
            fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
        )
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer incoming",
                ],
                body: ByteBuffer(
                    string: #"{"model":"\#(slug)","input":"keep","stream":true}"#
                )
            )

            #expect(response.status == .ok)
            #expect(response.headers[.contentType] == "text/event-stream")
            #expect(response.headers[.connection] == nil)
            let stream = try #require(String(data: data(response.body), encoding: .utf8))
            #expect(stream.contains("event: response.created\n"))
            #expect(stream.contains(#""delta":"OK""#))
            #expect(stream.contains("event: response.completed\n"))
        }

        let upstream = try #require(await transport.requests.first)
        #expect(upstream.url == "https://api.z.ai/api/coding/paas/v4/chat/completions")
        #expect(upstream.headers["authorization"] == ["Bearer selected-secret"])
        let body = try #require(
            JSONSerialization.jsonObject(with: upstream.body) as? [String: Any]
        )
        #expect(body["model"] as? String == "glm-5.2")
        #expect(body["stream"] as? Bool == true)
        #expect(body["tool_stream"] == nil)
        #expect(
            (body["stream_options"] as? [String: Any])?["include_usage"] as? Bool
                == true
        )
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[0]["content"] as? String == "keep")
        #expect(await fixture.state.claudeSessionRequestCount == 0)
        #expect(await fixture.state.codexSessionRequestCount == 1)
    }

    @Test("A provider pinned to native stays protocol-transparent")
    func nativeResponsesForwarding() async throws {
        let base = try makeFixture()
        let original = base.snapshot.providers[0]
        let provider = Provider(
            id: original.id,
            name: "OpenAI compatible",
            baseURL: "https://example.com/api",
            authMode: original.authMode,
            models: original.models,
        )
        let snapshot = RoutingSnapshot(
            generation: base.snapshot.generation,
            providers: [provider],
            mappings: base.snapshot.mappings,
            codex: base.snapshot.codex
        )
        let fixture = GatewayFixture(
            snapshot: snapshot,
            state: GatewayState(snapshot: snapshot),
            secrets: base.secrets
        )
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                chunks: ["event: response.created\n", "data: {}\n\n"]
            )
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let mapping = try #require(fixture.snapshot.codex.resolvedDefaultModel(in: [provider]))
        let slug = CodexCatalog.slug(for: mapping, in: [provider])

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(
                    string: #"{"model":"\#(slug)","input":"keep","stream":true}"#
                )
            )
            #expect(response.status == .ok)
            #expect(String(buffer: response.body) == "event: response.created\ndata: {}\n\n")
        }

        let upstream = try #require(await transport.requests.first)
        #expect(upstream.url == "https://example.com/api/v1/responses")
        let body = try #require(
            JSONSerialization.jsonObject(with: upstream.body) as? [String: Any]
        )
        #expect(body["input"] as? String == "keep")
        #expect(body["stream"] as? Bool == true)
    }
}

@Suite("Gateway Responses adapter live streaming")
struct GatewayResponsesLiveTests {
    @Test("z.ai returns before reading and awaits every public frame write")
    func lazyStreamingAndBackpressure() async throws {
        let fixture = try GatewayTests().makeFixture()
        let stageRecorder = StreamingStageRecorder(
            blockingMarker: #""delta":"FIRST""#
        )
        let upstreamBody = DemandTrackedBodySequence(
            chunks: try gatewayChatCompletionChunks(),
            gatedNextCall: 1,
            recorder: stageRecorder
        )
        let transport = RecordingGatewayTransport(responses: [
            gatewayChatStreamingResponse(upstreamBody)
        ])
        let traffic = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: traffic
        )
        let context = try gatewayLiveChatContext(fixture: fixture)

        let responseTask = Task {
            let response = try await responder.chatCompletionsResponsesResponse(context)
            await stageRecorder.responseReturned()
            return response
        }
        let firstStage = await stageRecorder.waitForFirstStage()
        #expect(firstStage == .responseReturned)
        guard firstStage == .responseReturned else {
            await upstreamBody.releaseGate()
            _ = try? await responseTask.value
            return
        }

        let response = try await responseTask.value
        #expect(response.status == .ok)
        #expect(response.headers[.contentType] == "text/event-stream")
        #expect(response.body.contentLength == nil)
        #expect(await upstreamBody.nextCallCount == 0)

        let requests = await transport.requests
        let request = try #require(requests.first)
        let requestBody = try #require(
            JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        #expect(requestBody["stream"] as? Bool == true)
        #expect(requestBody["tool_stream"] as? Bool == true)
        #expect(
            (requestBody["stream_options"] as? [String: Any])?["include_usage"] as? Bool
                == true
        )
        let trafficEvent = try #require(traffic.events.first)
        #expect(trafficEvent.streaming)
        #expect(trafficEvent.upstreamExchanges.first?.request?.streaming == true)

        let responseBody = response.body
        let bodyTask = Task {
            try await responseBody.write(
                ObservingResponseBodyWriter(recorder: stageRecorder)
            )
        }
        await stageRecorder.waitUntilContains(#""delta":"FIRST""#)
        #expect(await upstreamBody.nextCallCount == 1)
        #expect(!(await stageRecorder.bodyString).contains(" SECOND"))

        await stageRecorder.releaseBlockedWrite()
        await upstreamBody.waitForNextCallCount(2)
        #expect(!(await stageRecorder.bodyString).contains(" SECOND"))
        await upstreamBody.releaseGate()
        try await bodyTask.value

        let publicBody = await stageRecorder.body
        let events = try ResponsesStreamingTestSupport.events(publicBody)
        #expect(
            events.map(\.name) == [
                "response.created",
                "response.in_progress",
                "response.output_item.added",
                "response.content_part.added",
                "response.output_text.delta",
                "response.output_text.delta",
                "response.output_text.done",
                "response.content_part.done",
                "response.output_item.done",
                "response.completed",
            ]
        )
        #expect(events.map(\.sequenceNumber) == Array(0..<events.count))
        let itemID = "msg_resp_chatcmpl_gateway_live"
        #expect(events[4].payload["item_id"] as? String == itemID)
        #expect(events[5].payload["item_id"] as? String == itemID)
        let terminal = try #require(events.last?.payload["response"] as? [String: Any])
        #expect(terminal["id"] as? String == "resp_chatcmpl_gateway_live")
        #expect(terminal["status"] as? String == "completed")
        let output = try #require(terminal["output"] as? [[String: Any]])
        #expect(output.first?["id"] as? String == itemID)
        #expect(await stageRecorder.finishCount == 1)
    }

    @Test("Non-streaming z.ai Responses remains buffered")
    func bufferedResponseIsUnchanged() async throws {
        let fixture = try GatewayTests().makeFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: #"""
                    {
                      "id": "chatcmpl_buffered",
                      "created": 7,
                      "choices": [{
                        "finish_reason": "stop",
                        "message": {"role": "assistant", "content": "BUFFERED"}
                      }],
                      "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}
                    }
                    """#
            )
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let response = try await responder.chatCompletionsResponsesResponse(
            gatewayLiveChatContext(
                fixture: fixture,
                streaming: false,
                includeTools: false
            )
        )

        #expect(response.headers[.contentType] == "application/json")
        let responseData = try await responseBodyData(response.body)
        let root = try #require(
            JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        )
        #expect(root["status"] as? String == "completed")
        let request = try #require(await transport.requests.first)
        let requestBody = try #require(
            JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        #expect(requestBody["stream"] as? Bool == false)
        #expect(requestBody["tool_stream"] == nil)
    }
}
