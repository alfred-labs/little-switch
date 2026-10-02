import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Stream failure boundary diagnostics")
struct GatewayStreamDiagnosticsTests {
    @Test("An HTTP native exchange identifies the actual selected transport")
    func selectedHTTPTransport() async throws {
        let fixture = try GatewayTests().makeFixture()
        let traffic = TrafficTestRecorder()
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: #"{"output":[]}"#)])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport, trafficRecorder: traffic)
        try await app.test(.router) { client in
            _ = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: #"{"model":"gpt-6-astra","input":"synthetic"}"#))
        }
        let event = try #require(traffic.events.first)
        #expect(
            event.annotations?.contains { $0.kind == "upstream-transport" && $0.message.contains("transport=http") }
                == true)
        #expect(event.annotations?.contains { $0.message.contains("transport=websocket") } == false)
    }

    @Test("A failed upstream read is not reported as a downstream disconnect", arguments: [true, false])
    func upstreamRead(native: Bool) async throws {
        let stream = AsyncThrowingStream<ByteBuffer, any Error> { continuation in
            continuation.yield(ByteBuffer(string: "data"))
            continuation.finish(throwing: HTTPClientError.remoteConnectionClosed)
        }
        let eventID = UUID()
        let (response, traffic) = try await recordedResponse(.stream(stream), native: native, eventID: eventID)
        await #expect(throws: HTTPClientError.remoteConnectionClosed) { _ = try await responseBodyData(response.body) }
        let event = try #require(traffic.events.first)
        #expect(event.id == eventID)
        #expect(event.lifecycle == .failed)
        #expect(event.failure?.kind == "stream")
        #expect(event.failure?.message.contains("upstream-read") == true)
        #expect(event.failure?.message.contains("HTTPClientError.remoteConnectionClosed") == true)
        #expect(event.failure?.message.contains("upstreamBytes=4 downstreamBytes=4") == true)
        #expect(event.failure?.message.contains(eventID.uuidString) == true)
    }

    @Test(
        "Client write and finish failures retain their boundary without private details", arguments: [true, false],
        [false, true])
    func downstreamWrite(native: Bool, finishing: Bool) async throws {
        let eventID = UUID()
        let (response, traffic) = try await recordedResponse(
            .bytes(ByteBuffer(string: "data")), native: native, eventID: eventID)
        await #expect {
            try await response.body.write(DisconnectingDiagnosticWriter(finishing: finishing))
        } throws: { error in
            type(of: error) is NSError.Type
                && (error as NSError).domain == "private-diagnostic-secret" && (error as NSError).code == 54
        }
        let event = try #require(traffic.events.first)
        #expect(event.lifecycle == .failed)
        #expect(event.failure?.message.contains(finishing ? "downstream-finish" : "downstream-write") == true)
        #expect(event.failure?.message.contains("NSError(code: 54)") == true)
        #expect(event.failure?.message.contains("upstreamBytes=4 downstreamBytes=\(finishing ? 4 : 0)") == true)
        #expect(event.failure?.message.contains(eventID.uuidString) == true)
        #expect(event.failure?.message.contains("private-diagnostic-secret") == false)
    }

    @Test("Stream cancellation remains cancellation", arguments: [true, false])
    func cancellation(native: Bool) async throws {
        let stream = AsyncThrowingStream<ByteBuffer, any Error> { $0.finish(throwing: CancellationError()) }
        let (response, traffic) = try await recordedResponse(.stream(stream), native: native)
        await #expect(throws: CancellationError.self) { _ = try await responseBodyData(response.body) }
        #expect(traffic.events.first?.lifecycle == .cancelled)
        #expect(traffic.events.first?.failure == nil)
    }

    @Test(
        "A disconnect while sending a protocol-error frame still identifies the downstream boundary",
        arguments: [false, true])
    func protocolErrorWrite(finishing: Bool) async throws {
        let stream = AsyncThrowingStream<ByteBuffer, any Error> {
            $0.finish(throwing: ProviderToolContract.Error.providerOwnedTool)
        }
        let (response, traffic) = try await recordedResponse(.stream(stream), native: false, errorStyle: .openAI)
        await #expect {
            try await response.body.write(DisconnectingDiagnosticWriter(finishing: finishing))
        } throws: { error in
            type(of: error) is NSError.Type
                && (error as NSError).domain == "private-diagnostic-secret" && (error as NSError).code == 54
        }
        let message = try #require(traffic.events.first?.failure?.message)
        #expect(message.contains(finishing ? "downstream-finish" : "downstream-write"))
        #expect(message.contains("NSError(code: 54)"))
        #expect(!message.contains("private-diagnostic-secret"))
    }

    @Test("An unreformatted protocol error still identifies its upstream read boundary")
    func protocolErrorRead() async throws {
        let stream = AsyncThrowingStream<ByteBuffer, any Error> {
            $0.finish(throwing: ProviderToolContract.Error.providerOwnedTool)
        }
        let (response, traffic) = try await recordedResponse(.stream(stream), native: false)
        await #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
            _ = try await responseBodyData(response.body)
        }
        #expect(
            traffic.events.first?.annotations?.contains {
                $0.kind == "stream-boundary" && $0.message.contains("upstream-read")
            } == true)
    }

    private func recordedResponse(
        _ body: HTTPClientResponse.Body,
        native: Bool,
        eventID: UUID = UUID(),
        errorStyle: GatewayResponder.ErrorStyle? = nil
    ) async throws -> (Response, TrafficTestRecorder) {
        let fixture = try GatewayTests().makeFixture()
        let traffic = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: traffic)
        let upstream = HTTPClientResponse(status: .ok, headers: ["content-type": "text/event-stream"], body: body)
        let response =
            native
            ? responder.nativeResponsesStream(upstream, eventID: eventID)
            : responder.streamingResponse(upstream, eventID: eventID, attempt: 0, errorStyle: errorStyle)
        return (responder.recordingClientResponse(response, eventID: eventID), traffic)
    }
}

private struct DisconnectingDiagnosticWriter: ResponseBodyWriter {
    let finishing: Bool

    mutating func write(_ buffer: ByteBuffer) async throws {
        if !finishing { throw Self.failure }
    }

    consuming func finish(_ trailingHeaders: HTTPFields?) async throws { throw Self.failure }

    private static var failure: NSError {
        NSError(
            domain: "private-diagnostic-secret",
            code: 54,
            userInfo: [NSLocalizedDescriptionKey: "private-diagnostic-secret"])
    }
}
