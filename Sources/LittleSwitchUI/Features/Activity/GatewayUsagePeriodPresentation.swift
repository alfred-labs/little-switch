import LittleSwitchCommon
import LittleSwitchCore

extension GatewayUsageStatsPresentation {
    public struct Period: Equatable, Sendable {
        public let label: String
        public let tokenTotal: String
        public let accessibilityValue: String
        public let metrics: [Metric]

        init(label: String, days: [GatewayUsageSummary.DayDetail]) {
            self.label = label
            let estimated = days.contains(where: \.tokensAreEstimated)
            let tokens = Self.sum(days, \.tokens)
            tokenTotal = GatewayUsageFormat.tokenTotal(tokens)
            accessibilityValue = Self.accessibilityValue(label: label, tokens: tokens, estimated: estimated)
            // The ratio uses unsaturated floating-point sums. Two very busy
            // days must not read 100% errors just because requests hit Int.max.
            let requests = days.reduce(0.0) { $0 + Double($1.requests) }
            let failures = Self.failures(days)
            metrics = [
                Metric(
                    id: "input-tokens",
                    title: estimated ? "Input tokens (est.)" : "Input tokens",
                    value: GatewayUsageFormat.compactCount(Self.sum(days, \.inputTokens)),
                    isLeading: false
                ),
                Metric(
                    id: "cached-tokens",
                    title: "Cached tokens",
                    value: GatewayUsageFormat.compactCount(Self.sum(days, \.cachedTokens)),
                    isLeading: false
                ),
                Metric(
                    id: "output-tokens",
                    title: "Output tokens",
                    value: GatewayUsageFormat.compactCount(Self.sum(days, \.outputTokens)),
                    isLeading: false
                ),
                Metric(
                    id: "requests",
                    title: "Requests",
                    value: GatewayUsageFormat.count(Self.sum(days, \.requests)),
                    isLeading: true
                ),
                Metric(
                    id: "errors",
                    title: "Errors",
                    value: failures.map { GatewayUsageFormat.errorRate(failures: $0, requests: requests) }
                        ?? GatewayUsageFormat.placeholder,
                    isLeading: true
                ),
                Metric(
                    id: "web-searches",
                    title: "Web searches",
                    value: Self.sum(days, \.webSearchCount).map(GatewayUsageFormat.count)
                        ?? GatewayUsageFormat.placeholder,
                    isLeading: true
                ),
            ]
        }

        static func accessibilityValue(label: String, tokens: Int, estimated: Bool) -> String {
            let value = "\(label), \(GatewayUsageFormat.count(tokens)) tokens"
            return estimated ? "\(value), includes estimates" : value
        }

        private static func sum(
            _ days: [GatewayUsageSummary.DayDetail],
            _ keyPath: KeyPath<GatewayUsageSummary.DayDetail, Int>
        ) -> Int {
            days.reduce(0) { total, day in
                let (sum, overflow) = total.addingReportingOverflow(day[keyPath: keyPath])
                return overflow ? Int.max : sum
            }
        }

        private static func failures(_ days: [GatewayUsageSummary.DayDetail]) -> Double? {
            var total = 0.0
            for day in days {
                guard let failures = day.failures else { return nil }
                total += Double(failures)
            }
            return total
        }

        private static func sum(
            _ days: [GatewayUsageSummary.DayDetail],
            _ keyPath: KeyPath<GatewayUsageSummary.DayDetail, Int?>
        ) -> Int? {
            var total = 0
            for day in days {
                guard let value = day[keyPath: keyPath] else { return nil }
                let (sum, overflow) = total.addingReportingOverflow(value)
                total = overflow ? Int.max : sum
            }
            return total
        }
    }
}
