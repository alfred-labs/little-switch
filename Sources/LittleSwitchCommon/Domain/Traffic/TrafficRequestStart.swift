import Foundation

public struct TrafficRequestStart: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var method: String
    public var path: String
    public var headers: [TrafficHeader]

    public init(
        startedAt: Date,
        method: String,
        path: String,
        headers: [TrafficHeader]
    ) {
        self.startedAt = startedAt
        self.method = method
        self.path = path
        self.headers = headers
    }
}
