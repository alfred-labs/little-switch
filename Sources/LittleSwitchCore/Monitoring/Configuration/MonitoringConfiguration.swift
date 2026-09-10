import Foundation

public enum MonitoringSignal: String, Codable, Equatable, CaseIterable, Sendable {
    case metrics
    case logs
}

public enum MonitoringAuthentication: String, Codable, Equatable, CaseIterable, Sendable {
    case none
    case bearer
}

public enum MonitoringLevel: String, Codable, Equatable, CaseIterable, Comparable, Sendable {
    case info
    case warn
    case error

    public var severityNumber: Int {
        switch self {
        case .info: 9
        case .warn: 13
        case .error: 17
        }
    }

    public static func < (lhs: MonitoringLevel, rhs: MonitoringLevel) -> Bool {
        lhs.severityNumber < rhs.severityNumber
    }
}

public struct MonitoringDestination: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var endpoint: String
    public var authentication: MonitoringAuthentication
    /// An opaque Keychain reference; destination configuration never contains the token.
    public var credentialID: UUID?

    public init(
        enabled: Bool = false,
        endpoint: String = "",
        authentication: MonitoringAuthentication = .none,
        credentialID: UUID? = nil
    ) {
        self.enabled = enabled
        self.endpoint = endpoint
        self.authentication = authentication
        self.credentialID = credentialID
    }
}

public struct MonitoringConfiguration: Codable, Equatable, Sendable {
    enum Error: Swift.Error, Equatable, Sendable {
        case invalidMetricInterval
        case missingCredential(MonitoringSignal)
    }

    public static let metricIntervalSecondsRange = 5...300

    public var exposeMetrics: Bool
    public var exposeLogs: Bool
    public var metrics: MonitoringDestination
    public var logs: MonitoringDestination
    public var metricIntervalSeconds: Int
    public var minimumLogLevel: MonitoringLevel

    public init(
        exposeMetrics: Bool = true,
        exposeLogs: Bool = false,
        metrics: MonitoringDestination = .init(),
        logs: MonitoringDestination = .init(),
        metricIntervalSeconds: Int = 15,
        minimumLogLevel: MonitoringLevel = .info
    ) {
        self.exposeMetrics = exposeMetrics
        self.exposeLogs = exposeLogs
        self.metrics = metrics
        self.logs = logs
        self.metricIntervalSeconds = metricIntervalSeconds
        self.minimumLogLevel = minimumLogLevel
    }

    package func validate() throws {
        guard Self.metricIntervalSecondsRange.contains(metricIntervalSeconds) else {
            throw Error.invalidMetricInterval
        }
        try validate(metrics, signal: .metrics)
        try validate(logs, signal: .logs)
    }

    private func validate(_ destination: MonitoringDestination, signal: MonitoringSignal) throws {
        if destination.enabled || !destination.endpoint.isEmpty {
            _ = try MonitoringEndpoint.validate(destination.endpoint)
        }
        if destination.enabled, destination.authentication == .bearer, destination.credentialID == nil {
            throw Error.missingCredential(signal)
        }
    }
}
