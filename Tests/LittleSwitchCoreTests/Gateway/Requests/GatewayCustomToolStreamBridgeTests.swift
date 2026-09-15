import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Streaming custom bridge model exchange")
struct GatewayCustomToolStreamBridgeTests {
    @Test("Both stream validators retain custom input while tracing only provider bytes", arguments: [false, true])
    func stream(chat: Bool) async throws {
        let provider = Provider(name: "Test", baseURL: "https://unit.example/v1", authMode: .none)
        let url = provider.baseURL + (chat ? "/chat/completions" : "/responses")
        let cache = CustomToolCapabilityCache()
        let key = CustomToolCapabilityKey(
            providerID: provider.id, modelID: "m", endpoint: url, wire: chat ? "chatCompletions" : "responses")
        _ = try await cache.mode(for: key) { .functionEnvelope }
        let body = Data(
            (chat
                ? #"{"tools":[{"type":"custom","custom":{"name":"exec"}}]}"#
                : #"{"tools":[{"type":"custom","name":"exec"}]}"#).utf8)
        let raw = try streamBytes(chat: chat)
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                body: .stream(DemandTrackedBodySequence(chunks: raw.map { Data([$0]) })))
        ])
        let recorder = TrafficTestRecorder()
        let state = GatewayState(
            snapshot: RoutingSnapshot(generation: 0, providers: [provider], mappings: [:]),
            customToolCapabilities: cache)
        let responder = GatewayResponder(
            state: state, transport: transport, secretStore: MemorySecretStore(), trafficRecorder: recorder)
        let traffic = TrafficUpstreamRequest(
            attempt: 0,
            claudeRoute: "m",
            providerID: provider.id,
            providerName: provider.name,
            modelID: "m",
            url: url,
            headers: [],
            body: body,
            streaming: true)
        let exchange = try await responder.executeModelRequest(
            HTTPClientRequest(url: url),
            body: body,
            traffic: traffic,
            wire: chat ? .chatCompletions : .responses,
            eventID: UUID(),
            attempt: 0)
        let output = try await exchange.trace.collect(exchange.response.body, upTo: 65_536)
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 65_536)
        let frames = try decoder.append(ByteBuffer(bytes: output)) + decoder.finish()
        let final = try JSONValue.parse(#require(frames.last { !$0.terminal }).data)
        let call =
            chat
            ? final.object?["choices"]?.array?.first?.object?["delta"]?.object?["tool_calls"]?.array?.first
            : final.object?["response"]?.object?["output"]?.array?.first
        #expect(call?.object?["type"] == .string(chat ? "custom" : "custom_tool_call"))
        #expect((chat ? call?.object?["custom"] : call)?.object?["input"] == .string(" x\r\n🐈"))
        let recorded = try #require(recorder.events.first?.upstreamExchanges.first)
        #expect(await recorded.request?.body == transport.requests.first?.body)
        #expect(recorded.response.body == raw)
    }

    private func streamBytes(chat: Bool) throws -> Data {
        let arguments = try CustomToolInputEnvelope.encode(" x\r\n🐈")
        let item: JSONValue = .object([
            "type": .string("function_call"), "id": .string("fc"), "call_id": .string("call"),
            "name": .string("exec"), "arguments": .string(arguments),
        ])
        let chunks: [JSONValue]
        if chat {
            let call: JSONValue = .object([
                "index": .integer(0), "id": .string("call"), "type": .string("function"),
                "function": .object(["name": .string("exec"), "arguments": .string(arguments)]),
            ])
            chunks = [
                .object([
                    "choices": .array([
                        .object([
                            "index": .integer(0), "finish_reason": .string("tool_calls"),
                            "delta": .object(["role": .string("assistant"), "tool_calls": .array([call])]),
                        ])
                    ])
                ])
            ]
        } else {
            var added = try #require(item.object)
            added["arguments"] = .string("")
            chunks = [
                .object([
                    "type": .string("response.output_item.added"), "output_index": .integer(0),
                    "item": .object(added),
                ]),
                .object([
                    "type": .string("response.function_call_arguments.done"), "output_index": .integer(0),
                    "item_id": .string("fc"), "arguments": .string(arguments),
                ]),
                .object([
                    "type": .string("response.output_item.done"), "output_index": .integer(0), "item": item,
                ]),
                .object([
                    "type": .string("response.completed"), "response": .object(["output": .array([item])]),
                ]),
            ]
        }
        return Data((try chunks.map { "data: " + (try $0.serialized()) + "\n\n" }.joined() + "data: [DONE]\n\n").utf8)
    }
}
