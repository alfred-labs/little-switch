import Foundation

public struct TrafficFailureCompletion: Codable, Equatable, Sendable {
    public var status: Int?
    public var finishedAt: Date
    public var failure: TrafficFailure

    public init(status: Int?, finishedAt: Date, failure: TrafficFailure) {
        self.status = status
        self.finishedAt = finishedAt
        self.failure = failure
    }
}
