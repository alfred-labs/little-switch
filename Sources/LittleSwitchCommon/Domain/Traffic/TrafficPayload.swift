import Foundation

public struct TrafficPayload: Codable, Equatable, Sendable {
    public var headers: [TrafficHeader]
    public var body: Data

    public init(headers: [TrafficHeader] = [], body: Data = Data()) {
        self.headers = headers
        self.body = body
    }
}
