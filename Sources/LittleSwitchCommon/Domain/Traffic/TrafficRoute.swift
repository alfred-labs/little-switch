public struct TrafficRoute: Codable, Equatable, Sendable {
    public var client: GatewayClient
    public var modelIdentifier: String
    public var target: TrafficRouteTarget
    public var streaming: Bool

    public init(
        client: GatewayClient,
        modelIdentifier: String,
        target: TrafficRouteTarget,
        streaming: Bool
    ) {
        self.client = client
        self.modelIdentifier = modelIdentifier
        self.target = target
        self.streaming = streaming
    }
}
