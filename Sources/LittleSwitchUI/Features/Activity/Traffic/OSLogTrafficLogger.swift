import Foundation
import LittleSwitchCore
import OSLog

struct OSLogTrafficLogger: TrafficOperationalLogging {
    private let traffic = Logger(subsystem: ProductIdentity.logSubsystem, category: "traffic")
    private let store = Logger(
        subsystem: ProductIdentity.logSubsystem,
        category: "traffic-store"
    )

    init() {}

    func requestFinished(_ summary: TrafficOperationalSummary) {
        let fields = [
            "request id=\(summary.eventID.uuidString)",
            "method=\(summary.method)",
            "path=\(summary.path)",
            "route=\(summary.claudeRoute ?? "—")",
            "provider=\(summary.providerName ?? "—")",
            "model=\(summary.modelID ?? "—")",
            "lifecycle=\(summary.lifecycle.rawValue)",
            "status=\(summary.status ?? 0)",
            "request_bytes=\(summary.requestBytes)",
            "response_bytes=\(summary.responseBytes)",
        ].joined(separator: " ")
        traffic.info("\(fields, privacy: .public)")
    }

    func storeStateChanged(_ state: TrafficStoreOperationalState) {
        switch state {
        case .persistenceFailed(let message):
            store.error("persistence failed: \(message, privacy: .private)")
        case .persistenceRecovered:
            store.info("persistence recovered")
        case .corruptRecordIgnored(let segment):
            store.warning("ignored corrupt record in \(segment, privacy: .public)")
        }
    }
}
