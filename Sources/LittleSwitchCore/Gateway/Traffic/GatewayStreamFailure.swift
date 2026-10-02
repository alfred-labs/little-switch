import Foundation
import LittleSwitchCommon

/// Progress is owned by the forwarding task. Counts are payload bytes read and
/// successfully handed to the downstream writer, not provider/client acceptance.
struct GatewayStreamProgress {
    enum Boundary: String {
        case upstreamRead = "upstream-read"
        case downstreamWrite = "downstream-write"
        case downstreamFinish = "downstream-finish"
    }

    var boundary = Boundary.upstreamRead
    var upstreamBytes: UInt64 = 0
    var downstreamBytes: UInt64 = 0

    func failure(_ error: any Error) -> GatewayStreamFailure {
        GatewayStreamFailure(
            diagnostic: "\(boundary.rawValue); cause=\(GatewayUpstreamRequestFailure.summary(error)); "
                + "upstreamBytes=\(upstreamBytes) downstreamBytes=\(downstreamBytes)")
    }
}

/// Safe metadata only, never a replacement for the original thrown error.
struct GatewayStreamFailure: Sendable {
    let diagnostic: String

    func trafficFailure(eventID: UUID) -> TrafficFailure {
        TrafficFailure(kind: "stream", message: "Response streaming failed: \(diagnostic) (request \(eventID))")
    }
}

/// The response-writing task owns this capture. Error paths report once before
/// rethrowing; successful chunks require no actor hop. A task-local binding keeps
/// concurrent requests isolated without changing public body error contracts.
actor GatewayStreamDiagnostics {
    @TaskLocal static var current: GatewayStreamDiagnostics?
    private(set) var failure: GatewayStreamFailure?

    func record(_ failure: GatewayStreamFailure) {
        if self.failure == nil { self.failure = failure }
    }
}
