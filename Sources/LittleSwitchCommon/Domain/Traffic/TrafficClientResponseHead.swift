public struct TrafficClientResponseHead: Codable, Equatable, Sendable {
    public var status: Int
    public var headers: [TrafficHeader]

    public init(status: Int, headers: [TrafficHeader]) {
        self.status = status
        self.headers = headers
    }
}
