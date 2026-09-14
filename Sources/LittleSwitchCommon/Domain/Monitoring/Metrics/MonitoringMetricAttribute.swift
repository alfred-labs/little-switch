import Foundation

public enum MonitoringTokenType: String, CaseIterable, Sendable {
    case input, output
    case cacheRead = "cache_read"
    case cacheWrite = "cache_write"
}

public enum MonitoringMetricAttribute: Hashable, Sendable {
    case client(MonitoringClient)
    case route(MonitoringRoute)
    case providerID(UUID?)
    case outcome(MonitoringOutcome)
    case status(Int?)
    case tokenType(MonitoringTokenType)
    case admissionReason(MonitoringAdmissionOutcome)
    case dropReason(MonitoringDropReason)
    case signal(MonitoringSignal)
    case searchProvider(WebSearchProvider)
    case searchOutcome(MonitoringWebSearchOutcome)
    case overflow

    public var name: String {
        switch self {
        case .client: "client"
        case .route: "route"
        case .providerID: "provider_id"
        case .outcome, .searchOutcome: "outcome"
        case .status: "status"
        case .tokenType: "token_type"
        case .admissionReason, .dropReason: "reason"
        case .signal: "signal"
        case .searchProvider: "engine"
        case .overflow: "overflow"
        }
    }

    public var value: String {
        switch self {
        case .client(let value): value.rawValue
        case .route(let value): value.rawValue
        case .providerID(let value): value?.uuidString.lowercased() ?? "unknown"
        case .outcome(let value): value.rawValue
        case .status(let value): value.map(String.init) ?? "unknown"
        case .tokenType(let value): value.rawValue
        case .admissionReason(let value): value.rawValue
        case .dropReason(let value): value.rawValue
        case .signal(let value): value.rawValue
        case .searchProvider(let value): value.rawValue
        case .searchOutcome(let value): value.rawValue
        case .overflow: "true"
        }
    }
}

public enum MonitoringMetricValue: Equatable, Sendable {
    case counter(UInt64)
    case gauge(UInt64)
    case histogram(MonitoringHistogramSnapshot)
}
