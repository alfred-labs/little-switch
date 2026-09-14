import Foundation

public enum MonitoringOperation: String, Codable, Sendable {
    case gatewayStarted = "gateway.started"
    case gatewayStopped = "gateway.stopped"
    case test = "monitoring.test"

    package var message: String {
        switch self {
        case .gatewayStarted: "Gateway started."
        case .gatewayStopped: "Gateway stopped."
        case .test: "Monitoring export test."
        }
    }
}

/// A closed attribute schema: arbitrary header, body and error fields cannot be added.
public struct MonitoringLogAttributes: Encodable, Equatable, Sendable {
    public let requestID: UUID?
    public let client: MonitoringClient?
    public let route: MonitoringRoute?
    public let providerID: UUID?
    public let resolvedModel: String?
    public let statusCode: Int?
    public let durationSeconds: Double?
    public let outcome: MonitoringOutcome?
    public let errorKind: MonitoringErrorKind?
    public let usage: GatewayUsageTotals?
    public let estimatedInputTokens: Int?
    public let webSearchCount: Int?

    private enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case client, route
        case providerID = "provider_id"
        case resolvedModel = "resolved_model"
        case statusCode = "status"
        case durationSeconds = "duration_seconds"
        case outcome
        case errorKind = "error_type"
        case usage
        case estimatedInputTokens = "estimated_input_tokens"
        case webSearchCount = "web_search_count"
    }

    fileprivate init(observation: MonitoringObservation? = nil) {
        requestID = observation?.requestID
        client = observation?.client
        route = observation?.route
        providerID = observation?.providerID
        resolvedModel = observation?.resolvedModel
        statusCode = observation?.statusCode
        durationSeconds = observation?.durationSeconds
        outcome = observation?.outcome
        errorKind = observation?.errorKind
        usage = observation?.usage
        estimatedInputTokens = observation?.estimatedInputTokens
        webSearchCount = observation?.webSearchCount
    }
}

public struct MonitoringLogEntry: Encodable, Equatable, Sendable {
    public let eventID: UUID
    public let timestamp: Date
    public let observedAt: Date
    public let level: MonitoringLevel
    public let eventName: String
    public let message: String
    public let attributes: MonitoringLogAttributes
    public let truncated: Bool

    public init(observation: MonitoringObservation, eventID: UUID = UUID(), observedAt: Date = Date()) {
        self.eventID = eventID
        self.timestamp = observation.finishedAt
        self.observedAt = observedAt
        self.level = observation.outcome.level
        self.eventName = observation.outcome.eventName
        self.message = observation.outcome.message
        self.attributes = MonitoringLogAttributes(observation: observation)
        self.truncated = observation.truncated
    }

    private init(operation: MonitoringOperation, at date: Date, eventID: UUID) {
        self.eventID = eventID
        timestamp = date
        observedAt = date
        level = .info
        eventName = operation.rawValue
        message = operation.message
        attributes = MonitoringLogAttributes()
        truncated = false
    }

    public static func operation(_ event: MonitoringOperation, at date: Date = Date(), eventID: UUID = UUID()) -> Self {
        Self(operation: event, at: date, eventID: eventID)
    }
}

extension MonitoringOutcome {
    fileprivate var level: MonitoringLevel {
        switch self {
        case .success: .info
        case .clientError, .cancelled: .warn
        case .serverError, .transportError: .error
        }
    }

    fileprivate var eventName: String {
        switch self {
        case .success: "gateway.request.completed"
        case .cancelled: "gateway.request.cancelled"
        case .clientError, .serverError, .transportError: "gateway.request.failed"
        }
    }

    fileprivate var message: String {
        switch self {
        case .success: "Gateway request completed."
        case .clientError: "Gateway request rejected."
        case .serverError: "Provider returned a server error."
        case .transportError: "Gateway request transport failed."
        case .cancelled: "Gateway request cancelled."
        }
    }
}
