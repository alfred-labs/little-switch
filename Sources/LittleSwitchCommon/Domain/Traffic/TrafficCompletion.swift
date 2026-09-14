import Foundation

public struct TrafficCompletion: Codable, Equatable, Sendable {
    public var status: Int
    public var finishedAt: Date

    public init(status: Int, finishedAt: Date) {
        self.status = status
        self.finishedAt = finishedAt
    }
}
