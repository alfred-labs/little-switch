import Foundation

/// Rolling per-day gateway traffic, the source behind the menu's stats block.
///
/// The traffic log rotates in minutes under load, so nothing longer than a
/// session can be recovered from it. This history is the durable side: a few
/// hundred bytes per day, folded once as each request finishes.
public struct GatewayUsageHistory: Equatable, Sendable {
    /// Days kept on disk. The menu series spans the same window; the rest give
    /// the weekly and comparison figures room to stay correct across a missed
    /// day.
    public static let retainedDays = 30

    public private(set) var days: [GatewayUsageDay]

    public init(days: [GatewayUsageDay] = []) {
        self.days = days.sorted { $0.day < $1.day }.suffix(Self.retainedDays)
    }

    public mutating func fold(_ event: GatewayUsageEvent, calendar: Calendar = .current) {
        let key = Self.dayKey(for: event.finishedAt, calendar: calendar)
        if let index = days.firstIndex(where: { $0.day == key }) {
            days[index].fold(event)
        } else {
            var day = GatewayUsageDay(day: key)
            day.fold(event)
            days.append(day)
            days.sort { $0.day < $1.day }
            days = Array(days.suffix(Self.retainedDays))
        }
    }

    public func day(_ key: String) -> GatewayUsageDay? {
        days.first { $0.day == key }
    }

    /// The last `count` day keys ending today, oldest first.
    public static func dayKeys(
        endingAt date: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [String] {
        let today = calendar.startOfDay(for: date)
        return (0..<max(0, count)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map {
                dayKey(for: $0, calendar: calendar)
            }
        }
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        String(
            format: "%04d-%02d-%02d",
            calendar.component(.year, from: date),
            calendar.component(.month, from: date),
            calendar.component(.day, from: date)
        )
    }
}
