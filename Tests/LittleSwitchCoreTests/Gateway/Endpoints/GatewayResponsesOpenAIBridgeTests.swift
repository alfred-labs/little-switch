import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

private let openAIBridgeProviderID = UUID()

private func makeOpenAIBridgeFixture(
    wireOverride: ProviderResponsesWireOverride?
) throws -> GatewayFixture {
    let provider = Provider(
        id: openAIBridgeProviderID,
        name: "openai",
        baseURL: ProviderPreset.openAI.baseURL,
        authMode: .bearer,
        models: [DiscoveredModel(id: "gpt-5.5", maxTokens: 128_000)],
        responsesWireOverride: wireOverride
    )
    let snapshot = RoutingSnapshot(
        generation: 11,
        providers: [provider],
        mappings: [:],
        codex: CodexConfiguration(
            defaultModel: ModelMapping(providerID: openAIBridgeProviderID, modelID: "gpt-5.5")
        )
    )
    let state = GatewayState(snapshot: snapshot)
    let secrets = MemorySecretStore()
    try secrets.write("sk-openai-bridge", providerID: openAIBridgeProviderID)
    return GatewayFixture(snapshot: snapshot, state: state, secrets: secrets)
}

private let openAIBridgeIncoming = Data(
    #"""
    {"model":"openai/gpt-5.5",
     "instructions":"Follow the project rules.",
     "input":[
       {"type":"message","role":"user","content":[{"type":"input_text","text":"Inspect the bridge."}]},
       {"type":"function_call","call_id":"call_1","name":"read_file","arguments":"{\"path\":\"README.md\"}"},
       {"type":"function_call_output","call_id":"call_1","output":"Done"}
     ],
     "tools":[
       {"type":"function","name":"read_file","description":"Read a file.","parameters":{"type":"object"}}
     ],
     "tool_choice":"auto",
     "max_output_tokens":512}
    """#.utf8
)

extension GatewayTests {
    @Test("A probed native Responses verdict serves the OpenAI provider natively")
    func openAIBridgeNativeProbedWire() async throws {
        let fixture = try makeOpenAIBridgeFixture(wireOverride: nil)
        await fixture.state.responsesCapabilities.record(
            providerID: openAIBridgeProviderID, supportsNative: true
        )
        let nativeResponse = Data(
            #"""
            {"id":"resp_1","object":"response","status":"completed","model":"gpt-5.5",
             "output":[
               {"type":"reasoning","id":"rs_1","summary":[]},
               {"type":"message","role":"assistant","id":"msg_1",
                "content":[{"type":"output_text","text":"Bridge verified."}]},
               {"type":"function_call","call_id":"call_next","name":"read_file",
                "arguments":"{\"path\":\"Sources\"}","status":"completed"}
             ],
             "usage":{"input_tokens":9,"output_tokens":4,"total_tokens":13}}
            """#.utf8
        )
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: String(bytes: nativeResponse, encoding: .utf8) ?? "")
        ])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: HTTPRequest.Method.post,
                body: ByteBuffer(bytes: openAIBridgeIncoming)
            )
            #expect(result.status == .ok)
            #expect(data(result.body) == nativeResponse)
        }

        let request = try #require(await transport.requests.first)
        #expect(request.url == "https://api.openai.com/v1/responses")
        let body = try #require(
            JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        #expect(body["model"] as? String == "gpt-5.5")
        #expect(body["instructions"] as? String == "Follow the project rules.")
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.count == 3)
        #expect(input[1]["call_id"] as? String == "call_1")
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.first?["name"] as? String == "read_file")
    }

    @Test("A probed absent Responses verdict routes the OpenAI provider through the adapter")
    func openAIBridgeAdapterProbedWire() async throws {
        let fixture = try makeOpenAIBridgeFixture(wireOverride: nil)
        await fixture.state.responsesCapabilities.record(
            providerID: openAIBridgeProviderID, supportsNative: false
        )
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: responsesModelResponse(
                    id: "chatcmpl_bridge",
                    output: [
                        [
                            "type": "message",
                            "role": "assistant",
                            "content": [["type": "output_text", "text": "Bridge verified."]],
                        ],
                        [
                            "type": "function_call",
                            "call_id": "call_next",
                            "name": "read_file",
                            "arguments": "{\"path\":\"Sources\"}",
                        ],
                    ]
                )
            )
        ])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: openAIBridgeIncoming)
            )
            #expect(result.status == .ok)
            let projected = try #require(
                JSONSerialization.jsonObject(with: data(result.body)) as? [String: Any]
            )
            #expect(projected["object"] as? String == "response")
            #expect(projected["model"] as? String == "openai/gpt-5.5")
            let output = try #require(projected["output"] as? [[String: Any]])
            #expect(output.contains { ($0["type"] as? String) == "message" })
            #expect(
                output.contains {
                    ($0["type"] as? String) == "function_call"
                        && ($0["call_id"] as? String) == "call_next"
                }
            )
        }

        let request = try #require(await transport.requests.first)
        #expect(request.url == "https://api.openai.com/v1/chat/completions")
        let body = try #require(
            JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        #expect(body["model"] as? String == "gpt-5.5")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.compactMap { $0["role"] as? String }.contains("system"))
        #expect(messages.contains { ($0["tool_call_id"] as? String) == "call_1" })
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect((tools.first?["function"] as? [String: Any])?["name"] as? String == "read_file")
    }

    @Test("A chat-completions wire override forces the adapter deterministically")
    func openAIBridgeForcedAdapterWire() async throws {
        let fixture = try makeOpenAIBridgeFixture(wireOverride: .chatCompletions)
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: responsesModelResponse(
                    id: "chatcmpl_forced",
                    output: [
                        [
                            "type": "message",
                            "role": "assistant",
                            "content": [["type": "output_text", "text": "Forced adapter."]],
                        ]
                    ]
                )
            )
        ])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: openAIBridgeIncoming)
            )
            #expect(result.status == .ok)
            let projected = try #require(
                JSONSerialization.jsonObject(with: data(result.body)) as? [String: Any]
            )
            #expect(projected["status"] as? String == "completed")
        }

        let request = try #require(await transport.requests.first)
        #expect(request.url == "https://api.openai.com/v1/chat/completions")
    }
}
