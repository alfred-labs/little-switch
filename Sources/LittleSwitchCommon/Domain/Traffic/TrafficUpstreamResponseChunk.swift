import Foundation

public struct TrafficUpstreamResponseChunk: Codable, Equatable, Sendable {
    public var attempt: Int
    public var bytes: Data

    public init(attempt: Int, bytes: Data) {
        self.attempt = attempt
        self.bytes = bytes
    }
}
