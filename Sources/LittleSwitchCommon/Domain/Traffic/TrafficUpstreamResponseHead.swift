public struct TrafficUpstreamResponseHead: Codable, Equatable, Sendable {
    public var attempt: Int
    public var status: Int
    public var headers: [TrafficHeader]

    public init(attempt: Int, status: Int, headers: [TrafficHeader]) {
        self.attempt = attempt
        self.status = status
        self.headers = headers
    }
}
