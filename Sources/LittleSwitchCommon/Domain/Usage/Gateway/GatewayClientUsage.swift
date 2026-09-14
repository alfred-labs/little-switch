/// Usage and request counters attributed to one wire client for one day.
///
/// Reported usage and the estimate are kept apart so `tokens` can prefer
/// provider-reported numbers the same way the day total does.
public struct GatewayClientUsage: Codable, Equatable, Sendable {
    public var usage: GatewayUsageTotals
    public var estimatedTokens: Int
    /// Requests whose failure and web-search counters are recorded here.
    /// Older payloads contain only tokens, so their recorded count is zero.
    public var recordedRequests: Int
    public var failures: Int
    public var webSearchCount: Int

    public init(
        usage: GatewayUsageTotals = GatewayUsageTotals(),
        estimatedTokens: Int = 0,
        recordedRequests: Int = 0,
        failures: Int = 0,
        webSearchCount: Int = 0
    ) {
        self.usage = usage
        self.estimatedTokens = max(0, estimatedTokens)
        self.recordedRequests = max(0, recordedRequests)
        self.failures = max(0, failures)
        self.webSearchCount = max(0, webSearchCount)
    }

    private enum CodingKeys: String, CodingKey {
        case usage, estimatedTokens, recordedRequests, failures, webSearchCount
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            usage: try values.decode(GatewayUsageTotals.self, forKey: .usage),
            estimatedTokens: try values.decode(Int.self, forKey: .estimatedTokens),
            recordedRequests: try values.decodeIfPresent(Int.self, forKey: .recordedRequests) ?? 0,
            failures: try values.decodeIfPresent(Int.self, forKey: .failures) ?? 0,
            webSearchCount: try values.decodeIfPresent(Int.self, forKey: .webSearchCount) ?? 0
        )
    }

    /// Tokens for the client, preferring provider-reported usage and falling
    /// back to the gateway's own estimate for requests that reported none.
    public var tokens: Int {
        saturatedGatewayUsageSum(usage.total, estimatedTokens)
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            usage: lhs.usage + rhs.usage,
            estimatedTokens: saturatedGatewayUsageSum(lhs.estimatedTokens, rhs.estimatedTokens),
            recordedRequests: saturatedGatewayUsageSum(lhs.recordedRequests, rhs.recordedRequests),
            failures: saturatedGatewayUsageSum(lhs.failures, rhs.failures),
            webSearchCount: saturatedGatewayUsageSum(lhs.webSearchCount, rhs.webSearchCount)
        )
    }
}
