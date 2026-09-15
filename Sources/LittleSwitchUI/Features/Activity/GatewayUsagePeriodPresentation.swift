import Foundation
import LittleSwitchCommon
import LittleSwitchCore

extension GatewayUsageStatsPresentation {
    public struct Period: Equatable, Sendable {
        public let label: String
        public let tokenTotal: String
        public let accessibilityValue: String
        public let metrics: [Metric]
        private let locale: Locale

        init(
            label: String,
            days: [GatewayUsageSummary.DayDetail],
            locale: Locale = .current
        ) {
            self.label = label
            self.locale = locale
            let estimated = days.contains(where: \.tokensAreEstimated)
            let tokens = Self.sum(days, \.tokens)
            tokenTotal = GatewayUsageFormat.tokenTotal(tokens, locale: locale)
            accessibilityValue = Self.accessibilityText(
                label: label,
                tokens: tokens,
                estimated: estimated,
                locale: locale
            )
            // The ratio uses unsaturated floating-point sums. Two very busy
            // days must not read 100% errors just because requests hit Int.max.
            let requests = days.reduce(0.0) { $0 + Double($1.requests) }
            let failures = Self.failures(days)
            metrics = [
                Metric(
                    id: "input-tokens",
                    title: estimated
                        ? L10n.string("Input tokens (est.)", locale: locale)
                        : L10n.string("Input tokens", locale: locale),
                    value: GatewayUsageFormat.compactCount(Self.sum(days, \.inputTokens), locale: locale),
                    isLeading: false,
                    accessibilityValue: Self.metricAccessibility(
                        value: GatewayUsageFormat.compactCount(Self.sum(days, \.inputTokens), locale: locale),
                        locale: locale
                    )
                ),
                Metric(
                    id: "cached-tokens",
                    title: L10n.string("Cached tokens", locale: locale),
                    value: GatewayUsageFormat.compactCount(Self.sum(days, \.cachedTokens), locale: locale),
                    isLeading: false,
                    accessibilityValue: Self.metricAccessibility(
                        value: GatewayUsageFormat.compactCount(Self.sum(days, \.cachedTokens), locale: locale),
                        locale: locale
                    )
                ),
                Metric(
                    id: "output-tokens",
                    title: L10n.string("Output tokens", locale: locale),
                    value: GatewayUsageFormat.compactCount(Self.sum(days, \.outputTokens), locale: locale),
                    isLeading: false,
                    accessibilityValue: Self.metricAccessibility(
                        value: GatewayUsageFormat.compactCount(Self.sum(days, \.outputTokens), locale: locale),
                        locale: locale
                    )
                ),
                Metric(
                    id: "requests",
                    title: L10n.string("Requests", locale: locale),
                    value: GatewayUsageFormat.count(Self.sum(days, \.requests), locale: locale),
                    isLeading: true,
                    accessibilityValue: GatewayUsageFormat.count(Self.sum(days, \.requests), locale: locale)
                ),
                Metric(
                    id: "errors",
                    title: L10n.string("Errors", locale: locale),
                    value: failures.map {
                        GatewayUsageFormat.errorRate(
                            failures: $0,
                            requests: requests,
                            locale: locale
                        )
                    }
                        ?? GatewayUsageFormat.placeholder,
                    isLeading: true,
                    accessibilityValue: failures.map {
                        GatewayUsageFormat.errorRate(
                            failures: $0,
                            requests: requests,
                            locale: locale
                        )
                    }
                        ?? L10n.string("Unavailable for this period", locale: locale)
                ),
                Metric(
                    id: "web-searches",
                    title: L10n.string("Web searches", locale: locale),
                    value: Self.sum(days, \.webSearchCount).map {
                        GatewayUsageFormat.count($0, locale: locale)
                    }
                        ?? GatewayUsageFormat.placeholder,
                    isLeading: true,
                    accessibilityValue: Self.sum(days, \.webSearchCount).map {
                        GatewayUsageFormat.count($0, locale: locale)
                    }
                        ?? L10n.string("Unavailable for this period", locale: locale)
                ),
            ]
        }

        static func accessibilityText(
            label: String,
            tokens: Int,
            estimated: Bool,
            locale: Locale = .current
        ) -> String {
            let localizedTotal = L10n.string(
                "\(label), \(GatewayUsageFormat.count(tokens, locale: locale)) tokens",
                locale: locale
            )
            return estimated
                ? L10n.string("\(localizedTotal), includes estimates", locale: locale)
                : localizedTotal
        }

        private static func metricAccessibility(value: String, locale: Locale) -> String {
            value == GatewayUsageFormat.placeholder
                ? L10n.string("Unavailable for this period", locale: locale)
                : value
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
