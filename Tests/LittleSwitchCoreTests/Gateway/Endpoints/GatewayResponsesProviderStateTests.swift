import Foundation
import HTTPTypes
import HummingbirdTesting
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Custom reasoning survives its provider round trip and never reaches OpenAI", arguments: [false, true])
    func reasoningProviderRoundTrip(streaming: Bool) async throws {
        let fixture = try makeFixture()
        let original: [String: Any] = [
            "type": "reasoning", "id": "rs_long_native_looking_identifier",
            "summary": [["type": "summary_text", "text": "Visible summary"]],
            "encrypted_content": "custom-state",
        ]
        let output = try JSONSerialization.data(withJSONObject: [
            "id": "resp_custom", "status": "completed", "output": [original],
            "usage": ["input_tokens": 1, "output_tokens": 1],
        ])
        let outputText = try #require(String(bytes: output, encoding: .utf8))
        let stream = """
            : heartbeat
            id: provider-event-1
            retry: 500
            event: response.completed
            data: {"type":"response.completed",
            data: "response":\(outputText)}


            """
        let firstResponse =
            streaming
            ? streamingResponse(
                status: .ok, headers: ["content-type": "text/event-stream"], chunks: stream.map(String.init))
            : response(status: .ok, body: outputText)
        let transport = RecordingGatewayTransport(responses: [
            firstResponse,
            response(status: .accepted, body: "{}"),
            response(status: .accepted, body: "{}"),
        ])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(fixture: fixture, transport: transport, trafficRecorder: recorder)
        try await app.test(.router) { client in
            let first = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: #"{"model":"z.ai/glm-5.2","input":"Hello","stream":\#(streaming)}"#)
            )
            #expect(first.status == .ok)
            let root: [String: Any]
            if streaming {
                let bytes = data(first.body)
                let text = String(buffer: first.body)
                #expect(text.contains(": heartbeat\nid: provider-event-1\nretry: 500\n"))
                var decoder = ServerSentEventDecoder(maximumFrameBytes: 8_192)
                let frames = try decoder.append(ByteBuffer(bytes: bytes)) + decoder.finish()
                let frame = try #require(frames.first)
                let event = try #require(JSONSerialization.jsonObject(with: frame.data) as? [String: Any])
                root = try #require(event["response"] as? [String: Any])
            } else {
                root = try #require(JSONSerialization.jsonObject(with: data(first.body)) as? [String: Any])
            }
            let tagged = try #require((root["output"] as? [[String: Any]])?.first)
            #expect((tagged["encrypted_content"] as? String)?.contains("little_switch_reasoning") == true)
            let native: [String: Any] = [
                "type": "reasoning", "id": "rs_openai_original", "summary": [],
                "encrypted_content": "opaque-openai-state",
            ]
            let legacy: [String: Any] = [
                "type": "reasoning", "id": "rs_resp_12345", "summary": [],
                "encrypted_content": "legacy-ollama-state",
            ]
            let message: [String: Any] = ["type": "message", "role": "user", "content": "Continue"]
            for model in ["gpt-5.6-sol", "z.ai/glm-5.2"] {
                let body = try JSONSerialization.data(withJSONObject: [
                    "model": model, "input": [tagged, native, legacy, message],
                ])
                let next = try await client.execute(
                    uri: "/v1/responses",
                    method: .post,
                    headers: [.authorization: "Bearer synthetic"],
                    body: ByteBuffer(bytes: body)
                )
                #expect(next.status == .accepted)
            }
        }
        let requests = await transport.requests
        #expect(requests.count == 3)
        let recorded = recorder.events.flatMap(\.upstreamExchanges).compactMap(\.response.body)
        #expect(recorded.contains(streaming ? Data(stream.utf8) : output))
        let nativeBody = try #require(JSONSerialization.jsonObject(with: requests[1].body) as? [String: Any])
        let nativeItems = try #require(nativeBody["input"] as? [[String: Any]])
        #expect(nativeItems.compactMap { $0["id"] as? String } == ["rs_openai_original"])
        let customBody = try #require(JSONSerialization.jsonObject(with: requests[2].body) as? [String: Any])
        let customItems = try #require(customBody["input"] as? [[String: Any]])
        let reasoning = customItems.filter { $0["type"] as? String == "reasoning" }
        #expect(reasoning.count == 1)
        #expect(NSDictionary(dictionary: try #require(reasoning.first)) == NSDictionary(dictionary: original))
    }
}
