import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore
import Testing
// swift-format sorts case-sensitively; SwiftLint sorts case-insensitively.
// swiftlint:disable:next sorted_imports
import os

@testable import LittleSwitchCore

@Suite("Native upstream failure diagnostics")
struct GatewayNativeFailureDiagnosticsTests {
    @Test(
        "A native transport failure reaches the client and terminal log with the same request ID",
        arguments: ["/v1/responses", "/v1/images/generations", "/v1/images/edits"])
    func visibleFailure(path: String) async throws {
        let fixture = try GatewayTests().makeFixture()
        let transport = NativeDiagnosticFailureTransport(error: HTTPClientError.remoteConnectionClosed)
        let recorder = NativeDiagnosticRecorder()
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport, trafficRecorder: recorder)
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: path,
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"model":"gpt-6-astra","input":"Synthetic diagnostic request"}"#))
            #expect(result.status == .badGateway)
            let event = try #require(recorder.events.first)
            let message = "Provider request failed: HTTPClientError.remoteConnectionClosed (request \(event.id))"
            let expected: JSONValue = [
                "error": ["message": .string(message), "type": "invalid_request_error", "param": .null, "code": .null]
            ]
            #expect(try JSONValue.parse(Data(result.body.readableBytesView)) == expected)
            #expect(event.lifecycle == .failed)
            #expect(event.failure == TrafficFailure(kind: "transport", message: message))
            #expect(event.finalStatus == 502)
            let terminals = recorder.records.filter { record in
                switch record.action {
                case .failed, .completed, .cancelled: true
                default: false
                }
            }
            #expect(terminals.count == 1)
            #expect(terminals.first?.eventID == event.id)
        }
        #expect(await transport.requests == 1)
    }

    @Test("Private error details never reach the public or persisted diagnostic", arguments: NativeDiagnosticCase.all)
    func privateErrorDetails(diagnostic: NativeDiagnosticCase) async throws {
        let fixture = try GatewayTests().makeFixture()
        let transport = NativeDiagnosticFailureTransport(error: diagnostic.error)
        let recorder = NativeDiagnosticRecorder()
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport, trafficRecorder: recorder)
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"model":"gpt-6-astra","input":"Synthetic diagnostic request"}"#))
            let event = try #require(recorder.events.first)
            let message = "Provider request failed: \(diagnostic.summary) (request \(event.id))"
            #expect(result.status == .badGateway)
            #expect(
                try JSONValue.parse(Data(result.body.readableBytesView)).object?["error"]?.object?["message"]
                    == .string(message))
            #expect(event.failure == TrafficFailure(kind: "transport", message: message))
            #expect(!String(buffer: result.body).contains(NativeDiagnosticCase.privateValue))
            let persisted = try #require(String(data: JSONEncoder().encode(recorder.records), encoding: .utf8))
            #expect(!persisted.contains(NativeDiagnosticCase.privateValue))
        }
    }

    @Test("A native WebSocket connection failure retains its cause and request ID downstream")
    func webSocketFailure() async throws {
        let recorder = NativeDiagnosticRecorder()
        let websocket = NativeDiagnosticWebSocketTransport()
        let harness = try NativeResponsesSessionHarness(
            websocket: websocket, traffic: recorder)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-astra","input":"Synthetic diagnostic request"}"#)
        let response = try await harness.events.wait(type: "error")
        let event = try await eventually(description: "native WebSocket failure recorded") {
            recorder.events.first { $0.lifecycle == .failed }
        }
        let message = "Provider request failed: UpstreamWebSocketFailure.handshakeTimedOut (request \(event.id))"
        #expect(response["status"] == 502)
        #expect(response["error"]?.object?["message"] == .string(message))
        #expect(event.failure == TrafficFailure(kind: "transport", message: message))
        let terminals = recorder.records.filter { record in
            switch record.action {
            case .failed, .completed, .cancelled: true
            default: false
            }
        }
        #expect(terminals.count == 1)
        #expect(terminals.first?.eventID == event.id)
        #expect(await websocket.attempts == 1)
        #expect(await harness.http.requests.isEmpty)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "native WebSocket diagnostic cleanup")
    }

    @Test("Cancellation wins over a concurrent non-cancellation transport failure")
    func cancelledTransportFailure() async throws {
        let fixture = try GatewayTests().makeFixture()
        let transport = NativeDiagnosticFailureTransport(
            error: HTTPClientError.remoteConnectionClosed, cancelBeforeThrow: true)
        let recorder = NativeDiagnosticRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder)
        let request = Request(
            head: HTTPRequest(method: .post, scheme: "http", authority: "localhost", path: "/v1/responses"),
            body: .init(buffer: .init(string: #"{"model":"gpt-6-astra","input":"Synthetic diagnostic request"}"#)))
        let task = Task { try await responder.respond(to: request) }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(recorder.events.first?.lifecycle == .cancelled)
        #expect(recorder.events.first?.failure == nil)
        #expect(await transport.requests == 1)
    }
}

private struct NativeDiagnosticRecorder: TrafficRecording {
    private let aggregated = TrafficTestRecorder()
    private let storage = OSAllocatedUnfairLock(initialState: [TrafficRecord]())

    var events: [TrafficEvent] { aggregated.events }
    var records: [TrafficRecord] { storage.withLock { $0 } }

    func record(eventID: UUID, action: TrafficAction) {
        storage.withLock { records in
            records.append(.init(eventID: eventID, sequence: UInt64(records.count), timestamp: Date(), action: action))
        }
        aggregated.record(eventID: eventID, action: action)
    }
}

private actor NativeDiagnosticFailureTransport: UpstreamTransport {
    let error: any Error
    let cancelBeforeThrow: Bool
    private(set) var requests = 0

    init(error: any Error, cancelBeforeThrow: Bool = false) {
        self.error = error
        self.cancelBeforeThrow = cancelBeforeThrow
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        requests += 1
        if cancelBeforeThrow { withUnsafeCurrentTask { $0?.cancel() } }
        throw error
    }
}

private actor NativeDiagnosticWebSocketTransport: UpstreamWebSocketTransport {
    private(set) var attempts = 0

    func withConnection(
        _ request: UpstreamWebSocketRequest,
        operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void
    ) async throws {
        attempts += 1
        throw UpstreamWebSocketFailure(kind: .handshakeTimedOut)
    }
    func shutdown() async throws {}
}
