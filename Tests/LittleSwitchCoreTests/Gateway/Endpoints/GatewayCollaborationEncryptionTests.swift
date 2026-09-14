import Foundation
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway collaboration argument encryption")
struct GatewayCollaborationEncryptionTests {
    @Test("Native Responses projection marks plaintext mail in every public output slot", arguments: [false, true])
    func nativeProjection(streaming: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        await fixture.state.responsesCapabilities.record(
            providerID: fixture.snapshot.providers[0].id, supportsNative: true)
        let call: [String: Any] = [
            "id": "fc_mail", "type": "function_call", "call_id": "call_mail",
            "name": "collaboration__send_message", "arguments": #"{"target":"/root","message":"Synthetic update."}"#,
            "status": "completed",
        ]
        let terminal = responseObject(
            id: "resp_mail",
            createdAt: 10,
            status: "completed",
            output: [call],
            usage: ResponsesUsage(inputTokens: 1, outputTokens: 1))
        var added = call
        added["arguments"] = ""
        added["status"] = "in_progress"
        let events: [[String: Any]] = [
            [
                "type": "response.created",
                "response": responseObject(
                    id: "resp_mail", createdAt: 10, status: "in_progress", output: [], usage: nil),
            ],
            ["type": "response.output_item.added", "output_index": 0, "item": added],
            [
                "type": "response.function_call_arguments.done", "output_index": 0, "item_id": "fc_mail",
                "call_id": "call_mail", "name": "collaboration__send_message", "arguments": call["arguments"] as Any,
            ],
            ["type": "response.output_item.done", "output_index": 0, "item": call],
            ["type": "response.completed", "response": terminal],
        ]
        let encodedEvents = try events.map { event in
            let json = try #require(String(data: responseData(event), encoding: .utf8))
            return "event: \(event["type"] as? String ?? "")\ndata: \(json)\n\n"
        }
        let wire = encodedEvents.joined()
        let terminalJSON = try #require(String(data: responseData(terminal), encoding: .utf8))
        let upstream =
            streaming
            ? streamingResponse(
                status: .ok, headers: ["content-type": "text/event-stream"], chunks: wire.map(String.init))
            : response(status: .ok, body: terminalJSON)
        let transport = RecordingGatewayTransport(responses: [upstream])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)
        try await app.test(.router) { client in
            let body = try responseData([
                "model": "z.ai/glm-5.2", "input": "Send a synthetic status.", "stream": streaming,
                "tools": [
                    [
                        "type": "namespace", "name": "collaboration",
                        "tools": [
                            [
                                "type": "function", "name": "send_message",
                                "parameters": ["type": "object", "properties": [:]],
                            ]
                        ],
                    ]
                ],
            ])
            let result = try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: body))
            #expect(result.status == .ok)
            let items: [[String: Any]]
            if streaming {
                var decoder = ServerSentEventDecoder(maximumFrameBytes: 65_536)
                let frames = try decoder.append(result.body) + decoder.finish()
                items = try frames.flatMap { frame in
                    let payload = try responsesGatewayObject(frame.data)
                    if let item = payload["item"] as? [String: Any] { return [item] }
                    return (payload["response"] as? [String: Any])?["output"] as? [[String: Any]] ?? []
                }
                #expect(items.count == 3)
            } else {
                let object = try responsesGatewayObject(Data(result.body.readableBytesView))
                items = try #require(object["output"] as? [[String: Any]])
                #expect(items.count == 1)
            }
            for item in items {
                #expect(item["namespace"] as? String == "collaboration")
                #expect(item["name"] as? String == "send_message")
                #expect((item["encrypted_function_args"] as? [String])?.isEmpty == true)
            }
        }
    }

    @Test("Buffered Chat Completions mail opts out of encryption")
    func chatProjection() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: responseData([
                "model": "route", "input": "Send a status.",
                "tools": [
                    [
                        "type": "namespace", "name": "collaboration",
                        "tools": [
                            [
                                "type": "function", "name": "send_message",
                                "parameters": ["type": "object", "properties": [:]],
                            ]
                        ],
                    ]
                ],
            ]), targetModel: "upstream")
        let projected = try OpenAIResponsesChatCompletions.project(
            responseBody: responseData([
                "id": "chat_mail",
                "choices": [
                    [
                        "finish_reason": "tool_calls",
                        "message": [
                            "role": "assistant",
                            "tool_calls": [
                                [
                                    "id": "call_mail", "type": "function",
                                    "function": [
                                        "name": "collaboration__send_message",
                                        "arguments": #"{"target":"/root","message":"Synthetic update."}"#,
                                    ],
                                ]
                            ],
                        ],
                    ]
                ],
            ]), prepared: prepared)
        let root = try responsesGatewayObject(projected)
        let item = try #require((root["output"] as? [[String: Any]])?.first)
        #expect(item["namespace"] as? String == "collaboration")
        #expect((item["encrypted_function_args"] as? [String])?.isEmpty == true)
    }
}
