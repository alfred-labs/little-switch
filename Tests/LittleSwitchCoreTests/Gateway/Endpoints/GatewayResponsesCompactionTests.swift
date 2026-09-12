import Foundation
import HTTPTypes
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Custom Responses compaction returns a portable Codex v2 continuation")
    func customCompactionContinuation() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: compactionSummaryResponse())
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let request = try compactionRequest(model: "z.ai/glm-5.2")
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(bytes: request)
            )
            #expect(result.status == .ok)
            let text = try #require(String(bytes: data(result.body), encoding: .utf8))
            #expect(text.contains("response.output_item.done"))
            #expect(text.contains("little_switch_compaction"))
            #expect(text.contains("response.completed"))
        }
        let upstream = try #require(await transport.requests.first)
        let body = try #require(JSONSerialization.jsonObject(with: upstream.body) as? [String: Any])
        #expect(body["max_output_tokens"] == nil)
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.first?["name"] as? String == "create_summary")
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(!input.contains { $0["type"] as? String == "compaction_trigger" })
    }

    @Test(
        "Compaction trigger must be unique, final and streaming",
        arguments: [
            #"{"model":"z.ai/glm-5.2","stream":false,"input":[{"type":"message","role":"user","content":"Continue"},{"type":"compaction_trigger"}]}"#,
            #"{"model":"z.ai/glm-5.2","stream":true,"input":[{"type":"compaction_trigger"},{"type":"message","role":"user","content":"Continue"}]}"#,
            #"{"model":"z.ai/glm-5.2","stream":true,"input":[{"type":"compaction_trigger"},{"type":"compaction_trigger"}]}"#,
        ])
    func invalidCompactionControl(body: String) async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)
        try await app.test(.router) { client in
            let result = try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(string: body))
            #expect(result.status == .badRequest)
        }
        #expect(await transport.requests.isEmpty)
    }
}

func compactionRequest(model: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "model": model, "stream": true,
        "input": [
            ["type": "message", "role": "user", "content": "Continue the implementation."],
            [
                "type": "function_call", "call_id": "call_1", "name": "read", "namespace": "workspace",
                "arguments": "{}",
            ],
            ["type": "function_call_output", "call_id": "call_1", "output": "The current implementation."],
            ["type": "compaction_trigger"],
        ],
        "tools": [
            [
                "type": "namespace", "name": "workspace",
                "tools": [["type": "function", "name": "read", "parameters": ["type": "object"]]],
            ]
        ],
    ])
}

func compactionSummaryResponse() -> String {
    #"{"id":"resp_summary","object":"response","status":"completed","model":"upstream","output":["#
        + #"{"id":"fc_summary","type":"function_call","name":"create_summary","call_id":"summary_1","arguments":"{"#
        + #"\"summary\":\"Continue the implementation; the file was read.\",\"retain_item_ids\":[]}"}],"usage":{"input_tokens":20,"output_tokens":5,"total_tokens":25}}"#
}
