import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Native Responses stream outcomes")
struct GatewayNativeStreamOutcomeTests {
    @Test("SSE event names identify failures when the payload omits its type", arguments: ["error", "response.failed"])
    func eventNameFailure(type: String) async throws {
        let fixture = try GatewayTests().makeFixture()
        let traffic = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: traffic)
        let wire = "event: \(type)\ndata: {\"code\":\"invalid_encrypted_content\"}\n\n"
        let eventID = UUID()
        let response = responder.nativeResponsesStream(
            streamingResponse(status: .ok, headers: ["content-type": "text/event-stream"], chunks: [wire]),
            eventID: eventID)
        let output = try await responseBodyData(responder.recordingClientResponse(response, eventID: eventID).body)
        #expect(output == Data(wire.utf8))
        #expect(traffic.events.first?.lifecycle == .failed)
    }

    @Test("Diagnostic limits never truncate native provider bytes")
    func oversizedEventStillForwards() async throws {
        let fixture = try GatewayTests().makeFixture()
        let traffic = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            maximumErrorBytes: 64,
            requiredAuthorityPort: nil,
            trafficRecorder: traffic)
        let chunks = [
            "event: response.output_item.done\ndata: {\"type\":\"response.output_item.done\",\"item\":{\"encrypted_content\":\"",
            String(repeating: "x", count: 200),
            "\"}}\n\n",
            "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n",
        ]
        let eventID = UUID()
        let response = responder.nativeResponsesStream(
            streamingResponse(status: .ok, headers: ["content-type": "text/event-stream"], chunks: chunks),
            eventID: eventID)
        let output = try await responseBodyData(responder.recordingClientResponse(response, eventID: eventID).body)
        #expect(output == Data(chunks.joined().utf8))
        #expect(traffic.events.first?.lifecycle == .completed)
        #expect(traffic.events.first?.annotations?.contains { $0.kind == "native-stream-observation" } == true)
    }

    @Test("An unfinished diagnostic frame is forwarded without a parsing error")
    func incompleteObservationStillForwards() async throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil)
        let wire = "data: {\"type\":\"response.completed\"}"
        let response = responder.nativeResponsesStream(
            streamingResponse(status: .ok, headers: ["content-type": "text/event-stream"], chunks: [wire]),
            eventID: UUID())
        #expect(try await responseBodyData(response.body) == Data(wire.utf8))
    }

    @Test(
        "Native SSE errors stay byte-identical and record a failed request", arguments: ["error", "response.failed"],
        ["\n\n", "\r\r"])
    func nativeFailure(type: String, separator: String) async throws {
        let error: [String: Any] = [
            "type": "invalid_request_error", "code": "invalid_encrypted_content",
            "message": "Synthetic private provider detail", "param": NSNull(),
        ]
        let event: [String: Any] =
            type == "error"
            ? ["type": type, "error": error, "sequence_number": 1]
            : ["type": type, "response": ["id": "resp_fail", "status": "failed", "output": [], "error": error]]
        let json = try #require(String(data: responseData(event), encoding: .utf8))
        let wire = "event: \(type)\ndata: \(json)\(separator)"
        let fixture = try GatewayTests().makeFixture()
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .ok, headers: ["content-type": "text/event-stream"], chunks: wire.map(String.init))
        ])
        let traffic = TrafficTestRecorder()
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport, trafficRecorder: traffic)
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: #"{"model":"gpt-6-astra","input":"Synthetic probe","stream":true}"#))
            #expect(result.status == .ok)
            #expect(String(buffer: result.body) == wire)
        }
        let recorded = try #require(traffic.events.first)
        #expect(recorded.lifecycle == .failed)
        let failure = try #require(recorded.failure)
        #expect(failure.kind == "stream")
        #expect(!failure.message.contains("Synthetic private provider detail"))
        #expect(recorded.upstreamExchanges.first?.responseStatus == 200)
    }
}
