import Foundation

public struct TrafficWebSearch: Codable, Equatable, Sendable {
    public var provider: String
    public var query: String
    public var startedAt: Date
    public var finishedAt: Date
    public var resultCount: Int?
    public var failure: TrafficFailure?

    public init(
        provider: String,
        query: String,
        startedAt: Date,
        finishedAt: Date,
        resultCount: Int?,
        failure: TrafficFailure?
    ) {
        self.provider = provider
        self.query = query
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.resultCount = resultCount
        self.failure = failure
    }
}
