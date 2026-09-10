enum MonitoringFailure: Error, Equatable, CustomStringConvertible {
    case notReady(String)
    case rejectedPayload
    case notQueryable

    var description: String {
        switch self {
        case .notReady(let name):
            "\(name) is not ready. Start the lab with docker compose -f tools/monitoring/compose.yaml up -d"
        case .rejectedPayload:
            "The receiver rejected the synthetic JSON payload"
        case .notQueryable:
            "Synthetic OTLP data was not queryable within the deadline"
        }
    }
}
