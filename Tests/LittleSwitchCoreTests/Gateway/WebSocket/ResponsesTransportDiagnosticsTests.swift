import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Responses transport diagnostics", .timeLimit(.minutes(1)))
struct ResponsesTransportDiagnosticsTests {
    @Test("Wire error codes survive diagnostic rendering without private error descriptions")
    func safeWireError() throws {
        let traffic = TrafficTestRecorder()
        let eventID = UUID()
        var diagnostics = ResponsesUpstreamDiagnostics()
        diagnostics.begin(requestBytes: 7) { message in
            traffic.record(eventID: eventID, action: .annotation(.init(kind: "upstream-transport", message: message)))
        }
        var snapshot = UpstreamWebSocketDiagnostics()
        snapshot.underlyingError = NSError(
            domain: "private-wire-secret", code: 54, userInfo: [NSLocalizedDescriptionKey: "private-wire-secret"])
        diagnostics.record("failed", wire: snapshot, error: UpstreamWebSocketFailure(kind: .connectionLost))
        let messages = try #require(traffic.events.first?.annotations).map(\.message)
        #expect(messages.contains { $0.contains("wireCause=NSError(code: 54)") })
        #expect(messages.contains { $0.contains("compression=none") })
        #expect(messages.allSatisfy { !$0.contains("private-wire-secret") })
    }

    @Test("An early provider rejection ends its exchange diagnostic before a reused connection starts another")
    func rejectionThenReuse() async throws {
        let traffic = TrafficTestRecorder()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let connection = ResponsesUpstreamConnection(
            key: .init(provider: nil, endpoint: "https://example.invalid/responses", model: "model"),
            request: try UpstreamWebSocketRequest(url: #require(URL(string: "wss://example.invalid/responses"))),
            maximumBytes: 4_096
        ) { _ in }
        let runner = Task { await connection.run(transport: websocket) }
        defer { runner.cancel() }
        for index in 1...2 {
            let eventID = UUID()
            let request = Task {
                try await connection.exchange(
                    Data(#"{"type":"response.create","model":"model","input":[]}"#.utf8),
                    previousResponseID: nil,
                    observeControl: { _ in },
                    observeTransport: { message in
                        traffic.record(
                            eventID: eventID, action: .annotation(.init(kind: "upstream-transport", message: message)))
                    },
                    validateProvider: {})
            }
            defer { request.cancel() }
            try await websocket.waitForRequests(index)
            if index == 1 {
                try await websocket.publish(#"{"type":"error","status":429,"message":"private-rejection-detail"}"#)
            } else {
                try await websocket.publish(#"{"type":"response.created","response":{"id":"r2"}}"#)
                try await websocket.publish(#"{"type":"response.completed","response":{"id":"r2","output":[]}}"#)
            }
            let response = try await valueWithinTimeout(request, description: "diagnosed exchange")
            #expect(response.status.code == (index == 1 ? 429 : 200))
            _ = try await response.body.collect(upTo: 4_096)
            let messages = try #require(traffic.events.first { $0.id == eventID }?.annotations).map(\.message)
            if index == 1 {
                #expect(messages.contains { $0.contains("event=exchange-rejected") && $0.contains("status=429") })
            } else {
                #expect(messages.contains { $0.contains("event=exchange-start") && $0.contains("phase=idle") })
            }
            #expect(messages.allSatisfy { !$0.contains("private-rejection-detail") })
        }
        await connection.close()
        try await valueWithinTimeout(runner, description: "rejected exchange cleanup")
    }

    @Test(
        "A peer close before the first response remains visible with its numeric code",
        arguments: [UInt16(1_009), 1_013])
    func peerClosesBeforeResponse(code: UInt16) async throws {
        let traffic = TrafficTestRecorder()
        let websocket = DiagnosticClosingTransport(code: code)
        let harness = try NativeResponsesSessionHarness(websocket: websocket, traffic: traffic)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-astra","input":"Synthetic diagnostic"}"#)
        _ = try await eventually(description: "synthetic request submitted") {
            await websocket.sent ? true : nil
        }
        await websocket.closeGate.open()
        let response = try await harness.events.wait(type: "error")
        let event = try await eventually(description: "peer close failure recorded") {
            traffic.events.first { $0.lifecycle == .failed }
        }
        let diagnostics = (event.annotations ?? []).filter { $0.kind == "upstream-transport" }.map(\.message)
        #expect(diagnostics.contains { $0.contains("transport=websocket") })
        #expect(diagnostics.contains { $0.contains("peerCloseCode=\(code)") && $0.contains("event=failed") })
        #expect(diagnostics.contains { $0.contains("phase=awaiting-response") })
        #expect(diagnostics.allSatisfy { !$0.contains("Synthetic diagnostic") })
        #expect(await harness.http.requests.isEmpty)
        let message =
            "Provider request failed: UpstreamWebSocketFailure.connectionEnded (peerCloseCode: \(code)) (request \(event.id))"
        #expect(response["error"]?.object?["message"] == .string(message))
        #expect(event.failure?.message == message)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "diagnostic session cleanup")
    }

    @Test("Reused connections retain one connection ID while each turn gets its own diagnostics")
    func reusedConnection() async throws {
        let traffic = TrafficTestRecorder()
        let websocket = SyntheticResponsesWebSocketTransport()
        let harness = try NativeResponsesSessionHarness(websocket: websocket, traffic: traffic)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-astra","input":"first"}"#)
        _ = try await harness.events.wait(type: "response.completed")
        harness.enqueue(
            #"{"type":"response.create","model":"gpt-6-astra","previous_response_id":"resp_1","input":"second"}"#)
        _ = try await eventually(description: "two completed diagnostic turns") {
            traffic.events.filter { $0.lifecycle == .completed }.count == 2 ? true : nil
        }
        let events = traffic.events
        #expect(events.count == 2)
        let diagnostics = events.map { event in
            (event.annotations ?? []).filter { $0.kind == "upstream-transport" }.map(\.message)
        }
        let starts = diagnostics.compactMap { $0.first { $0.contains("event=exchange-start") } }
        #expect(starts.count == 2)
        let identifiers = starts.compactMap { $0.split(separator: " ").first { $0.hasPrefix("connection=") } }
        #expect(identifiers.count == 2)
        #expect(Set(identifiers).count == 1)
        #expect(starts.contains { $0.contains("exchange=1") })
        #expect(starts.contains { $0.contains("exchange=2") })
        #expect(await websocket.connections == 1)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "reused diagnostic session cleanup")
        #expect(
            traffic.events.allSatisfy { event in
                !(event.annotations ?? []).contains {
                    $0.kind == "upstream-transport" && $0.message.contains("event=failed")
                }
            })
    }
}

private actor DiagnosticClosingTransport: UpstreamWebSocketTransport {
    let closeGate = AsyncTestGate()
    let code: UInt16
    private(set) var sent = false

    init(code: UInt16) { self.code = code }

    func withConnection(
        _ request: UpstreamWebSocketRequest,
        operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void
    ) async throws {
        try await operation(
            .init(
                inbound: DiagnosticClosingInbound(gate: closeGate, code: code),
                outbound: DiagnosticClosingOutbound(owner: self)))
    }
    func shutdown() async throws {}
    func submitted() { sent = true }
}

private struct DiagnosticClosingInbound: UpstreamWebSocketInbound {
    let gate: AsyncTestGate
    let code: UInt16
    func consume(
        _ onMessage: @escaping @Sendable (UpstreamWebSocketMessage) async throws -> Void
    ) async throws -> UpstreamWebSocketPeerClose {
        try await gate.wait()
        return .init(code: code)
    }
}

private struct DiagnosticClosingOutbound: UpstreamWebSocketOutbound {
    let owner: DiagnosticClosingTransport
    func send(_ message: UpstreamWebSocketMessage) async throws { await owner.submitted() }
    func close(code: UInt16, reason: String?) async throws { await owner.closeGate.open() }
}
