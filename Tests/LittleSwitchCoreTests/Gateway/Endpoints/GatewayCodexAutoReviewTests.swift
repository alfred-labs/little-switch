import Foundation
import HummingbirdTesting
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

extension CodexAutoReviewTests {
    @Test(
        "Custom Responses reviewer requests preserve instructions, schema, and approval or denial output",
        arguments: ["allow", "deny"], [false, true])
    func nativeForwarding(decision: String, streaming: Bool) async throws {
        let fixture = makeGatewayFixture(wire: .native)
        let resultJSON = try JSONSerialization.data(withJSONObject: [
            "id": "resp_review", "object": "response", "status": "completed", "model": "xlarge",
            "output": [
                [
                    "id": "msg_review", "type": "message", "role": "assistant", "status": "completed",
                    "content": [["type": "output_text", "text": reviewDecision(decision), "annotations": []]],
                ]
            ],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
        ])
        let resultBody = try #require(String(data: resultJSON, encoding: .utf8))
        let completed = try JSONSerialization.data(withJSONObject: [
            "type": "response.completed", "response": JSONSerialization.jsonObject(with: resultJSON),
        ])
        let completedBody = try #require(String(data: completed, encoding: .utf8))
        let upstreamBody =
            streaming
            ? "event: response.completed\ndata: \(completedBody)\n\n"
            : resultBody
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .ok,
                headers: ["content-type": streaming ? "text/event-stream" : "application/json"],
                chunks: [upstreamBody])
        ])
        let recorder = TrafficTestRecorder()
        let app = GatewayTests().makeApplication(
            fixture: fixture, transport: transport, trafficRecorder: recorder)
        let request = try reviewRequest(streaming: streaming)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(bytes: request))
            #expect(result.status == .ok)
            #expect(String(buffer: result.body) == upstreamBody)
        }

        let requests = await transport.requests
        #expect(requests.count == 1)
        let upstream = try #require(requests.first)
        #expect(upstream.url == "https://example.com/v1/responses")
        var expected = try responsesGatewayObject(request)
        expected["model"] = "xlarge"
        #expect(try responsesGatewayObject(upstream.body) as NSDictionary == expected as NSDictionary)
        let event = try #require(recorder.events.first)
        #expect(event.claudeRoute == "little-switch-auto-review")
        #expect(event.modelID == "xlarge")
        #expect(await fixture.state.codexSessionRequestCount == 1)
        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 0)
    }

    @Test(
        "Custom Responses reviewer provider errors remain errors without a model fallback",
        arguments: [HTTPResponseStatus.notFound, .tooManyRequests, .internalServerError])
    func upstreamFailure(status: HTTPResponseStatus) async throws {
        let fixture = makeGatewayFixture(wire: .native)
        let errorBody = #"{"error":{"message":"Reviewer unavailable","type":"provider_error"}}"#
        let transport = RecordingGatewayTransport(responses: [response(status: status, body: errorBody)])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(bytes: try reviewRequest(streaming: false)))
            #expect(result.status.code == status.code)
            #expect(String(buffer: result.body) == errorBody)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("A reviewer without any exposed target is rejected before upstream dispatch")
    func unavailableTarget() async throws {
        let snapshot = RoutingSnapshot(generation: 1, providers: [], mappings: [:])
        let fixture = GatewayFixture(
            snapshot: snapshot, state: GatewayState(snapshot: snapshot), secrets: MemorySecretStore())
        let transport = RecordingGatewayTransport(responses: [])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(bytes: try reviewRequest(streaming: false)))
            #expect(result.status == .badRequest)
        }
        #expect(await transport.requests.isEmpty)
        #expect(await fixture.state.codexSessionRequestCount == 0)
    }

    @Test("The Chat Completions adapter routes the reviewer and preserves its decision", arguments: ["allow", "deny"])
    func adapterForwarding(decision: String) async throws {
        let fixture = makeGatewayFixture(wire: .chatCompletions)
        let decisionText = reviewDecision(decision)
        let chatResponse = try JSONSerialization.data(withJSONObject: [
            "id": "chat_review",
            "choices": [
                ["finish_reason": "stop", "message": ["role": "assistant", "content": decisionText]]
            ],
        ])
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: try #require(String(data: chatResponse, encoding: .utf8)))
        ])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(bytes: try reviewRequest(streaming: false)))
            #expect(result.status == .ok)
            let object = try responsesGatewayObject(data(result.body))
            #expect(object["model"] as? String == "little-switch-auto-review")
            let output = try #require(object["output"] as? [[String: Any]])
            let content = try #require(output.first?["content"] as? [[String: Any]])
            #expect(content.first?["text"] as? String == decisionText)
        }
        let upstream = try #require(await transport.requests.first)
        #expect(upstream.url == "https://example.com/v1/chat/completions")
        let object = try responsesGatewayObject(upstream.body)
        #expect(object["model"] as? String == "xlarge")
        #expect(
            object["messages"] as? [[String: String]] == [
                ["role": "system", "content": "Review this synthetic action against the supplied policy."],
                ["role": "user", "content": "Synthetic approval review fixture."],
            ])
    }

    private func makeGatewayFixture(wire: ProviderResponsesWireOverride) -> GatewayFixture {
        var snapshot = makeSnapshot()
        snapshot.providers[0].responsesWireOverride = wire
        snapshot.codex.autoReviewModel = snapshot.codex.defaultModel
        snapshot.codex.defaultModel = ModelMapping(providerID: snapshot.providers[0].id, modelID: "small")
        return GatewayFixture(
            snapshot: snapshot, state: GatewayState(snapshot: snapshot), secrets: MemorySecretStore())
    }

    private func reviewRequest(streaming: Bool) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "model": "little-switch-auto-review",
            "input": "Synthetic approval review fixture.",
            "instructions": "Review this synthetic action against the supplied policy.",
            "stream": streaming,
            "reasoning": ["effort": "low"],
            "text": [
                "format": [
                    "type": "json_schema", "name": "review", "strict": true,
                    "schema": [
                        "type": "object",
                        "properties": [
                            "outcome": ["type": "string", "enum": ["allow", "deny"]],
                            "risk_level": ["type": "string", "enum": ["low", "medium", "high", "critical"]],
                            "user_authorization": ["type": "string", "enum": ["unknown", "low", "medium", "high"]],
                            "rationale": ["type": "string"],
                        ],
                        "required": ["outcome"], "additionalProperties": false,
                    ],
                ]
            ],
        ])
    }

    private func reviewDecision(_ outcome: String) -> String {
        outcome == "allow"
            ? #"{"outcome":"allow"}"#
            : #"{"risk_level":"high","user_authorization":"low","outcome":"deny","rationale":"Synthetic denial fixture."}"#
    }
}
