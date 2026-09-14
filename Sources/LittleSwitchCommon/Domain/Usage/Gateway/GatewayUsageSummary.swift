import Foundation

/// What the status menu reads: the day series and its numeric metrics.
///
/// Values stay numeric and keys stay raw — display names, percentages, and
/// abbreviations belong to the presentation layer.
public struct GatewayUsageSummary: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public let day: String
        public let tokens: Int

        public init(day: String, tokens: Int) {
            self.day = day
            self.tokens = tokens
        }
    }

    /// One day of metrics, aggregated across the series at rest or displayed
    /// individually when the menu inspects a day.
    public struct DayDetail: Equatable, Sendable {
        public let requests: Int
        /// Nil when older mixed traffic cannot be attributed to this client.
        public let failures: Int?
        public let tokens: Int
        public let tokensAreEstimated: Bool
        public let inputTokens: Int
        public let cachedTokens: Int
        public let outputTokens: Int
        // Persisted like its web-search twin even though no menu cell reads
        // it today; the persistence round trip goes through this summary.
        // periphery:ignore
        public let toolSearchCount: Int
        /// Nil when older mixed traffic cannot be attributed to this client.
        public let webSearchCount: Int?

        public init(
            requests: Int,
            failures: Int?,
            tokens: Int,
            tokensAreEstimated: Bool,
            inputTokens: Int = 0,
            cachedTokens: Int = 0,
            outputTokens: Int = 0,
            toolSearchCount: Int = 0,
            webSearchCount: Int? = 0
        ) {
            self.requests = requests
            self.failures = failures
            self.tokens = tokens
            self.tokensAreEstimated = tokensAreEstimated
            self.inputTokens = inputTokens
            self.cachedTokens = cachedTokens
            self.outputTokens = outputTokens
            self.toolSearchCount = toolSearchCount
            self.webSearchCount = webSearchCount
        }

        /// The zeroed day, for projections that must render before any
        /// history exists.
        public static let empty = DayDetail(
            requests: 0,
            failures: 0,
            tokens: 0,
            tokensAreEstimated: false,
            toolSearchCount: 0,
            webSearchCount: 0
        )
    }

    /// Days plotted in the menu's series.
    public static let seriesDays = 30
    public let points: [Point]
    /// Aligned with `points`, oldest first, so a hovered bar index reads both.
    /// Today is the last entry: `today` projects it instead of storing the
    /// day twice, so a new per-day field lands in exactly one place.
    public let dayDetails: [DayDetail]

    /// Today, in the same shape as any series day. The series always spans
    /// `seriesDays` entries — quiet days included as zeroes — so the last
    /// one exists by construction.
    public var today: DayDetail {
        dayDetails[dayDetails.count - 1]
    }

    public init(
        history: GatewayUsageHistory,
        client: GatewayClient? = nil,
        now: Date,
        calendar: Calendar = .current
    ) {
        let seriesKeys = GatewayUsageHistory.dayKeys(
            endingAt: now,
            count: Self.seriesDays,
            calendar: calendar
        )
        let days = seriesKeys.map { history.day($0) }
        dayDetails = days.map { day in
            if let client {
                return Self.clientDayDetail(day, client: client)
            }
            return Self.dayDetail(day)
        }
        points = zip(seriesKeys, dayDetails).map {
            Point(
                day: $0,
                tokens: $1.tokens
            )
        }
    }

    private static func dayDetail(_ day: GatewayUsageDay?) -> DayDetail {
        let usage = day?.usage ?? GatewayUsageTotals()
        return DayDetail(
            requests: day?.requests ?? 0,
            failures: day?.failures ?? 0,
            tokens: day?.tokens ?? 0,
            tokensAreEstimated: day?.usesEstimatedTokens ?? false,
            // The gateway's own estimate is an input estimate, so it rides
            // the input cell and the three cells sum to `tokens`.
            inputTokens: saturatedGatewayUsageSum(usage.inputTokens, day?.estimatedTokens ?? 0),
            cachedTokens: saturatedGatewayUsageSum(
                usage.cacheReadTokens,
                usage.cacheWriteTokens
            ),
            outputTokens: usage.outputTokens,
            toolSearchCount: day?.toolSearchCount ?? 0,
            webSearchCount: day?.webSearchCount ?? 0
        )
    }

    private static func clientDayDetail(_ day: GatewayUsageDay?, client: GatewayClient) -> DayDetail {
        guard let day else { return .empty }
        let requests = max(0, day.clients[client.rawValue] ?? 0)
        guard requests > 0 else { return .empty }
        let attribution = day.clientUsage[client.rawValue] ?? GatewayClientUsage()
        let usage = attribution.usage
        return DayDetail(
            requests: requests,
            failures: clientCount(
                attribution.failures,
                total: day.failures,
                clientRequests: requests,
                recordedRequests: attribution.recordedRequests,
                dayRequests: day.requests
            ),
            tokens: attribution.tokens,
            tokensAreEstimated: attribution.estimatedTokens > 0,
            inputTokens: saturatedGatewayUsageSum(usage.inputTokens, attribution.estimatedTokens),
            cachedTokens: saturatedGatewayUsageSum(usage.cacheReadTokens, usage.cacheWriteTokens),
            outputTokens: usage.outputTokens,
            webSearchCount: clientCount(
                attribution.webSearchCount,
                total: day.webSearchCount,
                clientRequests: requests,
                recordedRequests: attribution.recordedRequests,
                dayRequests: day.requests
            )
        )
    }

    private static func clientCount(
        _ recorded: Int,
        total: Int,
        clientRequests: Int,
        recordedRequests: Int,
        dayRequests: Int
    ) -> Int? {
        // Saturated request counts are lower bounds, so their equality
        // cannot prove complete or exclusive client attribution.
        if clientRequests < Int.max, recordedRequests == clientRequests {
            return recorded
        }
        // Missing historic attribution is recoverable only from an exact
        // zero or a day entirely attributed to this client.
        if total == 0 || (dayRequests < Int.max && clientRequests == dayRequests) {
            return total
        }
        return nil
    }
}
