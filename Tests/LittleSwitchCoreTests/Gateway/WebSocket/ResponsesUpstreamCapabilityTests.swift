import Foundation
import HTTPTypes
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("WebSocket rejection route evidence", .timeLimit(.minutes(1)))
struct ResponsesUpstreamCapabilityTests {
    @Test("A WebSocket 404 or 405 preserves the error without poisoning HTTP routing", arguments: [404, 405])
    func webSocketRejection(status: Int) async throws {
        let image = try await GatewayImageFixture.make(wire: .responses)
        let fixture = GatewayFixture(
            snapshot: .init(generation: 0, providers: [image.provider], mappings: [:]),
            state: image.state,
            secrets: MemorySecretStore())
        let clock = ResolverTestClock()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let harness = try NativeResponsesSessionHarness(websocket: websocket, fixture: fixture, clock: clock)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","stream_id":"A","model":"example/model","input":"first"}"#)
        try await websocket.waitForRequests(1)
        // A successful upgrade alone must not teach a positive verdict either.
        #expect(await image.state.responsesCapabilities.verdict(for: image.provider.id) == nil)
        let error: JSONValue = [
            "type": "invalid_request_error", "code": "model_not_found", "message": "Synthetic model is unavailable",
            "param": "model",
        ]
        let event: JSONValue = ["type": "error", "status": .integer(status), "error": error]
        try await websocket.publish(#require(String(data: event.serializedData(), encoding: .utf8)))
        let rejection = try await harness.events.wait(type: "error", streamID: "A")
        #expect(rejection == ["type": "error", "status": .integer(status), "stream_id": "A", "error": error])
        #expect(await image.state.responsesCapabilities.verdict(for: image.provider.id) == nil)
        #expect(await harness.http.requests.isEmpty)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "WebSocket route rejection cleanup")

        // The same provider's subsequent HTTP POST must still use Responses.
        let http = RecordingGatewayTransport(responses: [
            response(status: .badRequest, body: #"{"error":{"message":"Synthetic HTTP rejection"}}"#)
        ])
        try await image.application(http).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"model":"example/model","input":"second","stream":false}"#))
            #expect(result.status == .badRequest)
        }
        #expect(await http.requests.map(\.url) == ["https://provider.example/v1/responses"])
        #expect(await image.state.responsesCapabilities.verdict(for: image.provider.id) == nil)
        await image.registry.shutdown()
    }

    @Test("An HTTP POST 404 or 405 still learns the missing route and retries the adapter", arguments: [404, 405])
    func httpRejection(status: Int) async throws {
        let image = try await GatewayImageFixture.make(wire: .responses)
        let http = RecordingGatewayTransport(responses: [
            response(status: .init(statusCode: status), body: #"{"error":{"message":"Synthetic route missing"}}"#),
            response(status: .ok, body: responsesModelResponse(id: "adapter_done", output: [])),
        ])
        try await image.application(http).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"model":"example/model","input":"first","stream":false}"#))
            #expect(result.status == .ok)
        }
        #expect(
            await http.requests.map(\.url) == [
                "https://provider.example/v1/responses", "https://provider.example/v1/chat/completions",
            ])
        #expect(await image.state.responsesCapabilities.verdict(for: image.provider.id) == false)
        await image.registry.shutdown()
    }
}
