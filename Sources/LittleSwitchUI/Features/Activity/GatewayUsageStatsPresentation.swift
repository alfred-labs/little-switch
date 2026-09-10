import Foundation
import LittleSwitchCore

/// Every menu graph and its metrics describe one period: the plotted thirty
/// days at rest, or the inspected day while the user explores the series.
public struct GatewayUsageStatsPresentation: Equatable, Sendable {
    public struct Metric: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let value: String
        public let isLeading: Bool

        var accessibilityValue: String {
            value == GatewayUsageFormat.placeholder ? "Unavailable for this period" : value
        }
    }

    /// Shared series identity and accessibility copy for Overview and clients.
    public struct DayDetail: Equatable, Identifiable, Sendable {
        public let id: String
        public let label: String
    }

    public let points: [Int]
    public let dayDetails: [DayDetail]
    public let axisLabels: [String]

    private let aggregate: Period
    private let days: [GatewayUsageSummary.DayDetail]

    public init(summary: GatewayUsageSummary) {
        points = summary.points.map(\.tokens)
        days = summary.dayDetails
        aggregate = Period(label: "\(summary.points.count) days", days: summary.dayDetails)
        dayDetails = summary.points.enumerated().map { index, point in
            let label = index == summary.points.count - 1 ? "Today" : Self.dayLabel(point.day)
            return DayDetail(
                id: point.day,
                label: label
            )
        }
        let lastIndex = summary.points.count - 1
        // GatewayUsageSummary always supplies thirty slots, including quiet days.
        axisLabels = [0, lastIndex / 2, lastIndex].map { Self.dayLabel(summary.points[$0].day) }
    }

    /// A nil selection restores the full period. Clamping keeps an accessible
    /// selection valid if the available series changes between updates.
    public func period(at index: Int?) -> Period {
        guard let index, !days.isEmpty else { return aggregate }
        let selected = min(max(index, 0), days.count - 1)
        return Period(label: dayDetails[selected].label, days: [days[selected]])
    }

    static func dayLabel(_ key: String) -> String {
        guard
            let date = try? Date(
                key,
                strategy: .iso8601.year().month().day()
            )
        else {
            return key
        }
        // A day key names a calendar day, not an instant. Keep both parsing
        // and formatting in UTC so western time zones do not read it early.
        var style = Date.FormatStyle.dateTime
            .locale(Locale(identifier: "en_US"))
            .month(.abbreviated)
            .day()
        style.timeZone = .gmt
        return date.formatted(style)
    }
}
