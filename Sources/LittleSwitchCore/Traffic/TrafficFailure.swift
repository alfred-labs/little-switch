import Foundation

public struct TrafficFailure: Codable, Equatable, Sendable {
    public var kind: String
    public var message: String

    public init(kind: String, message: String) {
        self.kind = kind
        self.message = message
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
