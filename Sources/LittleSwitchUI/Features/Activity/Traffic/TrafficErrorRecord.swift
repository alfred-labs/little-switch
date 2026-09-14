import Foundation
import LittleSwitchCommon
import LittleSwitchCore

/// A compact local index: no request/response bodies, headers or tool arguments.
struct TrafficErrorRecord: Codable, Equatable, Sendable {
    let eventID: UUID
    let timestamp: Date
    // These Codable fields are consumed by external log readers; there is no
    // in-process viewer. Keep the exceptions on the serialized fields only.
    // periphery:ignore
    let status: Int?
    // periphery:ignore
    let method: String?
    // periphery:ignore
    let path: String?
    // periphery:ignore
    let providerName: String?
    // periphery:ignore
    let modelID: String?
    // periphery:ignore
    let failure: TrafficFailure

    init?(record: TrafficRecord, event: TrafficEvent?) {
        guard case .failed(let completion) = record.action else { return nil }
        eventID = record.eventID
        timestamp = record.timestamp
        status = completion.status
        method = event.map { TrafficDiagnosticText.bounded($0.method) }
        path = event.map { TrafficDiagnosticText.bounded($0.path) }
        providerName = event?.providerName.map { TrafficDiagnosticText.bounded($0) }
        modelID = event?.modelID.map { TrafficDiagnosticText.bounded($0) }
        failure = TrafficFailure(
            kind: TrafficDiagnosticText.bounded(completion.failure.kind),
            message: TrafficDiagnosticText.bounded(completion.failure.message, limit: 2_048),
            toolName: completion.failure.toolName,
            toolNamespace: completion.failure.toolNamespace
        )
    }
}
