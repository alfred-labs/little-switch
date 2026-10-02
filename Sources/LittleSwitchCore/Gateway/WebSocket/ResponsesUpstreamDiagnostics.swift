import Foundation
import LittleSwitchTransport

/// Owned by the upstream connection actor. Observers are rebound for each turn;
/// snapshots are copied before suspension so late I/O cannot switch request IDs.
struct ResponsesUpstreamDiagnostics: Sendable {
    enum Phase: String {
        case connecting
        case sending
        case awaitingResponse = "awaiting-response"
        case streaming
        case idle
    }

    let connectionID = UUID()
    var phase = Phase.connecting
    var exchange = 0
    var requestBytes = 0
    var reportedFailure = false
    var peerClose: UpstreamWebSocketPeerClose?
    var snapshot: @Sendable () async -> UpstreamWebSocketDiagnostics? = { nil }
    private var observe: @Sendable (String) -> Void = { _ in }

    mutating func begin(requestBytes: Int, observer: @escaping @Sendable (String) -> Void) {
        exchange += 1
        self.requestBytes = requestBytes
        observe = observer
        reportedFailure = false
        record("exchange-start", wire: nil)
    }

    func record(_ event: String, wire: UpstreamWebSocketDiagnostics?, error: (any Error)? = nil) {
        var message =
            "transport=websocket connection=\(connectionID) exchange=\(exchange) event=\(event)"
            + " phase=\(phase.rawValue) requestBytes=\(requestBytes)"
        if let wire {
            message +=
                " writtenPayloadBytes=\(wire.writtenPayloadBytes) receivedPayloadBytes=\(wire.receivedPayloadBytes)"
                + " writtenDataFrames=\(wire.writtenDataFrames) receivedDataFrames=\(wire.receivedDataFrames)"
                + " compression=\(wire.compression.rawValue)"
                + " closeOrigin=\(wire.closeOrigin?.rawValue ?? "unobserved")"
            if let code = wire.localCloseCode { message += " localCloseCode=\(code)" }
            if let code = wire.peerCloseCode { message += " peerCloseCode=\(code)" }
            if let error = wire.underlyingError {
                message += " wireCause=\(GatewayUpstreamRequestFailure.summary(error))"
            }
        } else if let peerClose {
            // A non-NIO transport may only expose its validated close result.
            message += " closeOrigin=unobserved"
            if let code = peerClose.code { message += " peerCloseCode=\(code)" }
        }
        if let error { message += " cause=\(GatewayUpstreamRequestFailure.summary(error))" }
        if let failure = error as? UpstreamWebSocketFailure, let response = failure.response {
            message += " upgradeStatus=\(response.head.status.code)"
        }
        observe(message)
    }
}

extension GatewayResponder {
    func transportDiagnosticObserver(eventID: UUID, attempt: Int = 0) -> @Sendable (String) -> Void {
        { [trafficRecorder] message in
            trafficRecorder.record(
                eventID: eventID,
                action: .annotation(.init(kind: "upstream-transport", message: "attempt=\(attempt) \(message)")))
        }
    }
}
