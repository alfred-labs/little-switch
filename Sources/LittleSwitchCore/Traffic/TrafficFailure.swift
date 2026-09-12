import Foundation

public struct TrafficFailure: Codable, Equatable, Sendable {
    public var kind: String
    public var message: String
    public var toolName: String?
    public var toolNamespace: String?

    public init(kind: String, message: String, toolName: String? = nil, toolNamespace: String? = nil) {
        self.kind = kind
        self.message = message
        self.toolName = toolName.map { TrafficDiagnosticText.bounded($0) }
        self.toolNamespace = toolNamespace.map { TrafficDiagnosticText.bounded($0) }
    }
}

public enum TrafficLifecycle: String, Codable, Equatable, Sendable {
    case inProgress
    case completed
    case failed
    case cancelled
}

public enum TrafficInitialUsageEstimateSource: String, Codable, Equatable, Sendable {
    case provider
    case localDividedByFour
}

public enum TrafficProviderCountOutcome: String, Codable, Equatable, Sendable {
    case success
    case timeout
    case http
    case invalid
    case transport
    case circuitOpen
}
