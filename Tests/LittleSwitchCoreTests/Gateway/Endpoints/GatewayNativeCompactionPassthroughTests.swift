import Foundation
import HTTPTypes
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Native compaction and its continuation preserve the upstream protocol", arguments: [false, true])
    func nativeCompactionPassthrough(accountSession: Bool) async throws {
        let fixture = try makeFixture()
        let checkpoint: [String: Any] = ["type": "compaction", "encrypted_content": "native-checkpoint"]
        let chunks = [
            "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_native\",\"output\":[]}}\n\n",
            "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"type\":\"compaction\",",
            "\"encrypted_content\":\"native-checkpoint\"}}\n\n",
            "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_native\",\"status\":\"completed\",\"output\":[]}}\n\n",
        ]
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(status: .ok, headers: ["content-type": "text/event-stream"], chunks: chunks),
            response(status: .accepted, body: "continued"),
        ])
        let account = try #require(HTTPField.Name("ChatGPT-Account-ID"))
        let lite = try #require(HTTPField.Name("X-OpenAI-Internal-Codex-Responses-Lite"))
        let metadata = try #require(HTTPField.Name("X-Codex-Turn-Metadata"))
        var headers: HTTPFields = [
            .authorization: "Bearer synthetic", lite: "true", metadata: #"{"kind":"compaction"}"#,
        ]
        if accountSession { headers[account] = "synthetic-account" }
        let incomingHeaders = headers
        var body = try responsesStreamObject(compactionRequest(model: "gpt-6-astra"))
        body["reasoning"] = ["context": "all_turns", "effort": "max", "summary": "detailed"]
        body["instructions"] = "Original coding instructions"
        body["parallel_tool_calls"] = true
        let history = try #require(body["input"] as? [[String: Any]])
        body["input"] =
            [
                checkpoint,
                ["type": "reasoning", "id": "rs_native_opaque", "encrypted_content": "native-reasoning"],
                ["type": "configuration_update", "reasoning": ["context": "all_turns"]],
            ] + history
        let request = try responsesStreamData(body)
        body["input"] = [checkpoint, ["type": "message", "role": "user", "content": "Continue"]]
        let continuation = try responsesStreamData(body)
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, headers: incomingHeaders, body: ByteBuffer(bytes: request))
            #expect(result.status == .ok)
            #expect(result.headers[.contentType] == "text/event-stream")
            #expect(data(result.body) == Data(chunks.joined().utf8))
            let next = try await client.execute(
                uri: "/v1/responses", method: .post, headers: incomingHeaders, body: ByteBuffer(bytes: continuation))
            #expect(next.status == .accepted)
            #expect(String(buffer: next.body) == "continued")
        }
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.map(\.body) == [request, continuation])
        for upstream in requests {
            #expect(
                upstream.url
                    == (accountSession
                        ? "https://chatgpt.com/backend-api/codex/responses" : "https://api.openai.com/v1/responses"))
            #expect(upstream.headers["authorization"] == ["Bearer synthetic"])
            #expect(upstream.headers["chatgpt-account-id"] == (accountSession ? ["synthetic-account"] : []))
            #expect(upstream.headers["x-openai-internal-codex-responses-lite"] == ["true"])
            #expect(upstream.headers["x-codex-turn-metadata"] == [#"{"kind":"compaction"}"#])
        }
    }

    @Test("Native compaction relays upstream failures without retrying or rewriting history")
    func nativeCompactionFailurePassthrough() async throws {
        let fixture = try makeFixture()
        let failure = #"{"error":{"code":"context_length_exceeded","message":"Native compaction failed"}}"#
        let transport = RecordingGatewayTransport(responses: [response(status: .badRequest, body: failure)])
        let request = try compactionRequest(model: "gpt-6-astra")
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: request))
            #expect(result.status == .badRequest)
            #expect(String(buffer: result.body) == failure)
        }
        #expect(await transport.requests.map(\.body) == [request])
    }
}
