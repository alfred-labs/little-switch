import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Conditional custom bridge model exchange")
struct GatewayCustomToolBridgeTests {
    @Test(
        "Responses and Chat adapt only a cached non-native verdict and trace the actual bytes",
        arguments: [false, true])
    func nonNative(chat: Bool) async throws {
        try await exchange(chat: chat, mode: .functionEnvelope)
    }

    @Test("Native and inconclusive verdicts keep original bytes", arguments: [false, true])
    func native(chat: Bool) async throws {
        try await exchange(chat: chat, mode: .native)
        try await exchange(chat: chat, mode: .inconclusive)
    }

    private func exchange(chat: Bool, mode: CustomToolCapabilityMode) async throws {
        let provider = Provider(
            name: "Test",
            baseURL: "https://unit.example/v1",
            authMode: .none,
            models: [DiscoveredModel(id: "m")])
        let url = provider.baseURL + (chat ? "/chat/completions" : "/responses")
        let wire: ProviderToolContract.Wire = chat ? .chatCompletions : .responses
        let cache = CustomToolCapabilityCache()
        let key = CustomToolCapabilityKey(
            providerID: provider.id, modelID: "m", endpoint: url, wire: chat ? "chatCompletions" : "responses")
        _ = try await cache.mode(for: key) { mode }
        let original = Data(
            (chat
                ? #"{ "model":"m", "tools":[{"type":"custom","custom":{"name":"exec"}}], "messages":[{"role":"user","content":"go"}] }"#
                : #"{ "model":"m", "tools":[{"type":"custom","name":"exec"}], "input":"go" }"#).utf8)
        let custom =
            chat
            ? #"{"choices":[{"index":0,"message":{"tool_calls":[{"type":"custom","id":"a","custom":{"name":"exec","input":" x\r\n"}}]},"finish_reason":"tool_calls"}]}"#
            : #"{"output":[{"type":"custom_tool_call","id":"fc","call_id":"a","name":"exec","input":" x\r\n"}]}"#
        let function =
            chat
            ? #"""
            {
              "choices": [
                {
                  "index": 0,
                  "message": {
                    "tool_calls": [
                      {
                        "type": "function",
                        "id": "a",
                        "function": {
                          "name": "exec",
                          "arguments": "{\"input\":\" x\\r\\n\"}"
                        }
                      }
                    ]
                  },
                  "finish_reason": "tool_calls"
                }
              ]
            }
            """#
            : #"{"output":[{"type":"function_call","id":"fc","call_id":"a","name":"exec","arguments":"{\"input\":\" x\\r\\n\"}"}]}"#
        let raw = Data((mode == .functionEnvelope ? function : custom).utf8)
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(
                status: .ok, headers: ["content-type": "application/json"], body: .bytes(ByteBuffer(bytes: raw)))
        ])
        let recorder = TrafficTestRecorder()
        let state = GatewayState(
            snapshot: RoutingSnapshot(generation: 0, providers: [provider], mappings: [:]),
            customToolCapabilities: cache)
        let responder = GatewayResponder(
            state: state, transport: transport, secretStore: MemorySecretStore(), trafficRecorder: recorder)
        var request = HTTPClientRequest(url: url)
        request.method = .POST
        request.body = .bytes(ByteBuffer(bytes: original))
        let traffic = TrafficUpstreamRequest(
            attempt: 0,
            claudeRoute: "m",
            providerID: provider.id,
            providerName: provider.name,
            modelID: "m",
            url: url,
            headers: [],
            body: original,
            streaming: false)
        let exchange = try await responder.executeModelRequest(
            request, body: original, traffic: traffic, wire: wire, eventID: UUID(), attempt: 0)
        let output = try await exchange.trace.collect(exchange.response.body, upTo: 65_536)
        #expect(try JSONValue.parse(output) == JSONValue.parse(Data(custom.utf8)))
        let sent = try #require(await transport.requests.first)
        #expect(await transport.requests.count == 1)
        if mode == .functionEnvelope {
            let tool = try JSONValue.parse(sent.body).object?["tools"]?.array?.first
            #expect(tool?.object?["type"] == .string("function"))
        } else {
            #expect(sent.body == original)
            #expect(output == raw)
        }
        let recorded = try #require(recorder.events.first?.upstreamExchanges.first)
        #expect(recorded.request?.body == sent.body)
        #expect(recorded.response.body == raw)
    }
}
