import AsyncHTTPClient
import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway provider tool ownership")
struct GatewayPortableToolTests {
    @Test("A rejected live tool ends with a safe protocol error")
    func rejectsLiveTool() async throws {
        let fixture = try GatewayTests().makeFixture()
        let chunks = [
            try frame(
                "message_start",
                value: [
                    "type": "message_start",
                    "message": [
                        "id": "msg_1", "type": "message", "role": "assistant", "model": "upstream",
                        "content": [], "usage": ["input_tokens": 10, "output_tokens": 0],
                    ],
                ]),
            try frame(
                "content_block_start",
                value: [
                    "type": "content_block_start", "index": 0,
                    "content_block": ["type": "server_tool_use", "id": "srv_1", "name": "analyze_image", "input": [:]],
                ]),
        ]
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(status: .ok, headers: ["content-type": "text/event-stream"], chunks: chunks)
        ])
        let recorder = TrafficTestRecorder()
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport, trafficRecorder: recorder)
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(
                    string: #"{"model":"claude-opus-5","stream":true,"messages":[{"role":"user","content":"Hello"}]}"#)
            )
            #expect(result.status == .ok)
            let body = String(buffer: result.body)
            #expect(body.contains("api_error"))
            #expect(!body.contains("analyze_image"))
            #expect(!body.contains("message_stop"))
        }
        let exchange = try #require(recorder.events.first?.upstreamExchanges.first)
        #expect(exchange.responseStatus == 200)
        #expect(exchange.response.body == Data(chunks.joined().utf8))
    }

    @Test("Messages rejects newly emitted proprietary tools before returning JSON")
    func blocksServerOutput() async throws {
        let fixture = try GatewayTests().makeFixture()
        let providerBody = try JSONSerialization.data(withJSONObject: [
            "id": "msg_foreign",
            "content": [["type": "server_tool_use", "id": "srv_1", "name": "analyze_image", "input": [:]]],
            "usage": ["input_tokens": 1, "output_tokens": 1],
        ])
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(
                status: .ok,
                headers: ["content-type": "application/json"],
                body: .bytes(
                    ByteBuffer(bytes: providerBody)
                ))
        ])
        let recorder = TrafficTestRecorder()
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport, trafficRecorder: recorder)
        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(
                    string: #"{"model":"claude-opus-5","max_tokens":32,"messages":[{"role":"user","content":"Hello"}]}"#
                )
            )
            #expect(response.status == .badGateway)
            #expect(!String(buffer: response.body).contains("analyze_image"))
        }
        let exchange = try #require(recorder.events.first?.upstreamExchanges.first)
        #expect(exchange.responseStatus == 200)
        #expect(exchange.response.body == providerBody)
    }

    private func frame(_ name: String, value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return "event: \(name)\ndata: \(try #require(String(bytes: data, encoding: .utf8)))\n\n"
    }
}
