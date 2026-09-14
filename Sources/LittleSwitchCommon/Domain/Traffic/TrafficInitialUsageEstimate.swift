public struct TrafficInitialUsageEstimate: Codable, Equatable, Sendable {
    public var tokenCount: Int
    public var source: TrafficInitialUsageEstimateSource
    public var providerOutcome: TrafficProviderCountOutcome
    public var elapsedMilliseconds: Int

    public init(
        tokenCount: Int,
        source: TrafficInitialUsageEstimateSource,
        providerOutcome: TrafficProviderCountOutcome,
        elapsedMilliseconds: Int
    ) {
        self.tokenCount = tokenCount
        self.source = source
        self.providerOutcome = providerOutcome
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}
