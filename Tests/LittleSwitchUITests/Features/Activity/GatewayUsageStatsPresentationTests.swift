import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Gateway usage stats presentation")
struct GatewayUsageStatsPresentationTests {
    @Test("A quiet gateway keeps a complete thirty-day period and empty graph")
    func quietGateway() {
        let stats = presentation(days: [])
        let period = stats.period(at: nil)

        #expect(period.label == "30 days")
        #expect(period.tokenTotal == "0")
        #expect(period.accessibilityValue == "30 days, 0 tokens")
        #expect(period.metrics.map(\.value) == ["0", "0", "0", "0", "0%", "0"])
        #expect(stats.points == Array(repeating: 0, count: GatewayUsageSummary.seriesDays))
        #expect(
            stats.axisLabels == ["Jul 31", "Aug 14", "Aug 29"])
    }

    @Test("The headline and six metrics aggregate the plotted days with a weighted error rate")
    func aggregatePeriod() {
        let stats = presentation(days: busyDays)
        let period = stats.period(at: nil)

        #expect(period.label == "30 days")
        #expect(period.tokenTotal == "1.42M")
        #expect(
            period.accessibilityValue
                == "30 days, 1,416,000 tokens"
        )
        #expect(
            period.metrics == [
                metric("input-tokens", "Input tokens", "1.2M", leading: false),
                metric(
                    "cached-tokens",
                    "Cached tokens",
                    "200K",
                    leading: false
                ),
                metric("output-tokens", "Output tokens", "16K", leading: false),
                metric("requests", "Requests", "139", leading: true),
                metric("errors", "Errors", "14%", leading: true),
                metric("web-searches", "Web searches", "5", leading: true),
            ]
        )
        #expect(stats.points.suffix(2) == [1_210_000, 206_000])
    }

    @Test("A French period localizes its label, titles, numbers, and percentage")
    func frenchPeriod() {
        var day = GatewayUsageDay(day: "2026-08-29")
        day.requests = 12_345
        day.failures = 617
        day.webSearchCount = 2
        day.usage = GatewayUsageTotals(inputTokens: 1_200)
        let period = presentation(days: [day], locale: Locale(identifier: "fr_FR")).period(at: nil)

        #expect(period.label == "30 jours")
        #expect(period.tokenTotal == "1,2K")
        #expect(
            period.metrics.map(\.title) == [
                "Jetons d’entrée",
                "Jetons en cache",
                "Jetons de sortie",
                "Requêtes",
                "Erreurs",
                "Recherches web",
            ])
        #expect(
            period.metrics.map(\.value) == [
                "1,2K",
                "0",
                "0",
                "12\u{202f}345",
                "5\u{00a0}%",
                "2",
            ])
        #expect(period.accessibilityValue == "30 jours, 1\u{202f}200 jetons")
    }

    @Test("Selecting a day changes the headline and every metric to that day")
    func selectedPeriod() {
        let stats = presentation(days: busyDays)
        let yesterday = stats.period(at: 28)
        let today = stats.period(at: 29)

        #expect(yesterday.label == "Aug 28")
        #expect(yesterday.tokenTotal == "1.21M")
        #expect(
            yesterday.accessibilityValue
                == "Aug 28, 1,210,000 tokens"
        )
        #expect(
            yesterday.metrics.map(\.value)
                == ["1M", "200K", "10K", "100", "10%", "2"]
        )
        #expect(today.label == "Today")
        #expect(today.tokenTotal == "206K")
        #expect(
            today.metrics.map(\.value)
                == ["200K", "0", "6K", "39", "26%", "3"]
        )
        #expect(
            stats.period(at: nil).metrics.map(\.value)
                == ["1.2M", "200K", "16K", "139", "14%", "5"]
        )
    }

    @Test("Selection indices clamp to the first and last plotted day")
    func clampedSelection() {
        let stats = presentation(days: busyDays)

        #expect(stats.period(at: Int.min) == stats.period(at: 0))
        #expect(stats.period(at: Int.max) == stats.period(at: 29))
        #expect(stats.period(at: 0).label == "Jul 31")
        #expect(stats.period(at: 0).metrics.map(\.value) == ["0", "0", "0", "0", "0%", "0"])
    }

    @Test("Historical estimates label only periods that include them")
    func estimatedPeriods() {
        var yesterday = GatewayUsageDay(day: "2026-08-28")
        yesterday.usage = GatewayUsageTotals(
            inputTokens: 100, outputTokens: 10, cacheReadTokens: 20, cacheWriteTokens: 30)
        yesterday.estimatedTokens = 940
        var today = GatewayUsageDay(day: "2026-08-29")
        today.usage = GatewayUsageTotals(inputTokens: 5, outputTokens: 1)
        let stats = presentation(days: [yesterday, today])

        #expect(stats.period(at: nil).metrics[0].title == "Input tokens (est.)")
        #expect(stats.period(at: nil).metrics[0].value == "1K")
        #expect(stats.period(at: nil).tokenTotal == "1.11K")
        #expect(
            stats.period(at: nil).accessibilityValue
                == "30 days, 1,106 tokens, includes estimates"
        )
        #expect(stats.period(at: 28).metrics.map(\.value) == ["1K", "50", "10", "0", "0%", "0"])
        #expect(
            stats.period(at: 28).accessibilityValue
                == "Aug 28, 1,100 tokens, includes estimates"
        )
        #expect(stats.period(at: 29).metrics[0].title == "Input tokens")
        #expect(
            stats.period(at: 29).accessibilityValue
                == "Today, 6 tokens"
        )
    }

    @Test("Traffic outside the displayed thirty days does not enter the aggregate")
    func boundedPeriod() {
        var older = GatewayUsageDay(day: "2026-07-30")
        older.requests = 500
        older.usage = GatewayUsageTotals(inputTokens: 9_000_000)
        let stats = presentation(days: [older] + busyDays)

        #expect(stats.period(at: nil) == presentation(days: busyDays).period(at: nil))
    }

    @Test("Large totals saturate without distorting the weighted error rate")
    func saturatedPeriods() {
        let days = ["2026-08-28", "2026-08-29"].map { key in
            var day = GatewayUsageDay(day: key)
            day.requests = Int.max
            day.failures = Int.max / 2
            day.webSearchCount = Int.max
            day.usage = GatewayUsageTotals(
                inputTokens: Int.max,
                outputTokens: Int.max,
                cacheReadTokens: Int.max
            )
            return day
        }
        let period = presentation(days: days).period(at: nil)

        #expect(period.tokenTotal == "9223372036.85B")
        #expect(
            period.accessibilityValue
                == "30 days, 9,223,372,036,854,775,807 tokens"
        )
        #expect(period.metrics[3].value == "9,223,372,036,854,775,807")
        #expect(period.metrics[4].value == "50%")
        #expect(period.metrics[5].value == "9,223,372,036,854,775,807")
        #expect(
            period.metrics.prefix(3).map(\.value)
                == Array(repeating: "9223372037B", count: 3)
        )
    }

    @Test("Series identities and axis labels name actual dates while today keeps its period label")
    func seriesLabels() {
        let stats = presentation(days: busyDays)

        #expect(stats.dayDetails.count == stats.points.count)
        #expect(stats.dayDetails.first?.id == "2026-07-31")
        #expect(stats.dayDetails.first?.label == "Jul 31")
        #expect(stats.dayDetails.last?.id == "2026-08-29")
        #expect(stats.dayDetails.last?.label == "Today")
        #expect(
            stats.period(at: 29).accessibilityValue
                == "Today, 206,000 tokens"
        )
        #expect(stats.axisLabels.last == "Aug 29")
    }

    @Test("Day labels stay on the key's calendar day and malformed keys remain readable")
    func dayLabelsFollowTheKey() {
        func dayLabels(_ locale: Locale) -> [String] {
            ["2026-01-01", "2026-12-31", "2028-02-29"].map {
                GatewayUsageStatsPresentation.dayLabel($0, locale: locale)
            }
        }

        #expect(GatewayUsageStatsPresentation.dayLabel("not-a-date") == "not-a-date")
        #expect(dayLabels(Locale(identifier: "en_US")) == ["Jan 1", "Dec 31", "Feb 29"])
        #expect(dayLabels(Locale(identifier: "fr_FR")) == ["1 janv.", "31 déc.", "29 févr."])
    }
}

private func presentation(
    days: [GatewayUsageDay],
    locale: Locale = Locale(identifier: "en_US")
) -> GatewayUsageStatsPresentation {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return GatewayUsageStatsPresentation(
        summary: GatewayUsageSummary(
            history: GatewayUsageHistory(days: days),
            now: Date(timeIntervalSince1970: 1_788_000_000),
            calendar: calendar
        ),
        locale: locale
    )
}

private var busyDays: [GatewayUsageDay] {
    var yesterday = GatewayUsageDay(day: "2026-08-28")
    yesterday.requests = 100
    yesterday.failures = 10
    yesterday.webSearchCount = 2
    yesterday.usage = GatewayUsageTotals(inputTokens: 1_000_000, outputTokens: 10_000, cacheReadTokens: 200_000)
    var today = GatewayUsageDay(day: "2026-08-29")
    today.requests = 39
    today.failures = 10
    today.webSearchCount = 3
    today.usage = GatewayUsageTotals(inputTokens: 200_000, outputTokens: 6_000)
    return [yesterday, today]
}

private func metric(
    _ id: String,
    _ title: String,
    _ value: String,
    leading: Bool
) -> GatewayUsageStatsPresentation.Metric {
    GatewayUsageStatsPresentation.Metric(id: id, title: title, value: value, isLeading: leading)
}
