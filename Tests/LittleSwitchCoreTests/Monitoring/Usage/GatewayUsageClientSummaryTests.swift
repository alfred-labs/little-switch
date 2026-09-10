import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Gateway usage client summary")
struct GatewayUsageClientSummaryTests {
    @Test("An empty client history uses the same thirty-day series as Overview")
    func emptyHistory() {
        let now = date("2026-09-01T12:00:00Z")
        let summary = GatewayUsageSummary(
            history: GatewayUsageHistory(),
            client: .claude,
            now: now,
            calendar: utcCalendar
        )

        #expect(summary.points.count == GatewayUsageSummary.seriesDays)
        #expect(summary.points.first?.day == "2026-08-03")
        #expect(summary.points.last?.day == "2026-09-01")
        #expect(summary.points.allSatisfy { $0.tokens == 0 })
        #expect(summary.dayDetails == Array(repeating: .empty, count: GatewayUsageSummary.seriesDays))
        #expect(summary == GatewayUsageSummary(history: GatewayUsageHistory(), now: now, calendar: utcCalendar))
    }

    @Test("All six metrics and each plotted day stay isolated per client")
    func clientIsolation() throws {
        let now = date("2026-09-01T18:00:00Z")
        var history = GatewayUsageHistory()
        let events = [
            GatewayUsageEvent(
                finishedAt: date("2026-08-10T10:00:00Z"),
                outcome: .succeeded,
                client: .claude,
                usage: GatewayUsageTotals(inputTokens: 500, outputTokens: 100),
                webSearchCount: 4
            ),
            GatewayUsageEvent(
                finishedAt: now,
                outcome: .succeeded,
                client: .claude,
                usage: GatewayUsageTotals(inputTokens: 10, outputTokens: 5, cacheReadTokens: 3, cacheWriteTokens: 2),
                toolSearchCount: 80,
                webSearchCount: 2
            ),
            GatewayUsageEvent(
                finishedAt: now,
                outcome: .succeeded,
                client: .codex,
                estimatedInputTokens: 400,
                webSearchCount: 3
            ),
            GatewayUsageEvent(finishedAt: now, outcome: .failed, client: .codex, webSearchCount: 1),
            GatewayUsageEvent(finishedAt: now, outcome: .cancelled, client: .codex, webSearchCount: 2),
            GatewayUsageEvent(
                finishedAt: now,
                outcome: .failed,
                usage: GatewayUsageTotals(inputTokens: 1_000),
                webSearchCount: 20
            ),
        ]
        for event in events {
            history.fold(event, calendar: utcCalendar)
        }

        let claude = GatewayUsageSummary(history: history, client: .claude, now: now, calendar: utcCalendar)
        let codex = GatewayUsageSummary(history: history, client: .codex, now: now, calendar: utcCalendar)
        let overview = GatewayUsageSummary(history: history, now: now, calendar: utcCalendar)

        #expect(
            claude.today
                == GatewayUsageSummary.DayDetail(
                    requests: 1,
                    failures: 0,
                    tokens: 20,
                    tokensAreEstimated: false,
                    inputTokens: 10,
                    cachedTokens: 5,
                    outputTokens: 5,
                    webSearchCount: 2
                )
        )
        #expect(
            codex.today
                == GatewayUsageSummary.DayDetail(
                    requests: 3,
                    failures: 1,
                    tokens: 400,
                    tokensAreEstimated: true,
                    inputTokens: 400,
                    webSearchCount: 6
                )
        )
        let pastIndex = try #require(claude.points.firstIndex { $0.day == "2026-08-10" })
        #expect(
            claude.dayDetails[pastIndex]
                == GatewayUsageSummary.DayDetail(
                    requests: 1,
                    failures: 0,
                    tokens: 600,
                    tokensAreEstimated: false,
                    inputTokens: 500,
                    outputTokens: 100,
                    webSearchCount: 4
                )
        )
        #expect(codex.dayDetails[pastIndex] == .empty)
        #expect(claude.points.map(\.tokens) == claude.dayDetails.map(\.tokens))
        #expect(codex.points.map(\.tokens) == codex.dayDetails.map(\.tokens))
        #expect(overview.today.requests == 5)
        #expect(overview.today.failures == 2)
        #expect(overview.today.tokens == 1_420)
        #expect(overview.today.webSearchCount == 28)
    }

    @Test("Legacy mixed traffic keeps tokens while unavailable attribution stays unknown")
    func legacyMixedTraffic() {
        #expect(
            summary(of: legacyDay())
                == GatewayUsageSummary.DayDetail(
                    requests: 2,
                    failures: nil,
                    tokens: 19,
                    tokensAreEstimated: true,
                    inputTokens: 13,
                    cachedTokens: 4,
                    outputTokens: 2,
                    webSearchCount: nil
                )
        )
    }

    @Test("Folding new traffic cannot fill old gaps in mixed client attribution")
    func legacyAttributionRemainsIncomplete() {
        var day = legacyDay()
        day.fold(
            GatewayUsageEvent(
                finishedAt: date("2026-09-01T18:00:00Z"),
                outcome: .failed,
                client: .claude,
                webSearchCount: 2
            )
        )

        let detail = summary(of: day)

        #expect(day.clientUsage["claude"]?.recordedRequests == 1)
        #expect(detail.requests == 3)
        #expect(detail.tokens == 19)
        #expect(detail.failures == nil)
        #expect(detail.webSearchCount == nil)
    }

    @Test("An entire legacy day attributed to one client proves its counters")
    func legacySingleClient() {
        var day = legacyDay()
        day.requests = 2
        day.clients = ["claude": 2]

        let detail = summary(of: day)

        #expect(detail.requests == 2)
        #expect(detail.failures == 1)
        #expect(detail.webSearchCount == 4)
    }

    @Test("Each zero global counter proves a client zero independently", arguments: [(0, 4), (1, 0), (0, 0)])
    func legacyZeroCounts(failures: Int, webSearches: Int) {
        var day = legacyDay()
        day.failures = failures
        day.webSearchCount = webSearches

        let detail = summary(of: day)

        #expect(detail.failures == (failures == 0 ? 0 : nil))
        #expect(detail.webSearchCount == (webSearches == 0 ? 0 : nil))
    }

    @Test("A day with no requests from this client is entirely zero")
    func noClientRequests() {
        var day = legacyDay()
        day.clients = ["codex": day.requests]

        #expect(summary(of: day) == .empty)
    }

    @Test("Older request counts without client tokens never borrow global usage")
    func legacyWithoutClientUsage() {
        var day = legacyDay()
        day.usage = GatewayUsageTotals(inputTokens: 800, outputTokens: 90)
        day.estimatedTokens = 50
        day.clientUsage = [:]

        #expect(
            summary(of: day)
                == GatewayUsageSummary.DayDetail(
                    requests: 2,
                    failures: nil,
                    tokens: 0,
                    tokensAreEstimated: false,
                    webSearchCount: nil
                )
        )
    }

    @Test("A client projection saturates input, cache and chart totals")
    func saturatedMetrics() {
        var day = GatewayUsageDay(day: "2026-09-01")
        day.requests = 1
        day.failures = 1
        day.webSearchCount = 1
        day.clients = ["claude": 1]
        day.clientUsage = [
            "claude": GatewayClientUsage(
                usage: GatewayUsageTotals(
                    inputTokens: .max,
                    outputTokens: 1,
                    cacheReadTokens: .max,
                    cacheWriteTokens: 1
                ),
                estimatedTokens: 1,
                recordedRequests: 1,
                failures: 1,
                webSearchCount: 1
            )
        ]

        #expect(
            summary(of: day)
                == GatewayUsageSummary.DayDetail(
                    requests: 1,
                    failures: 1,
                    tokens: .max,
                    tokensAreEstimated: true,
                    inputTokens: .max,
                    cachedTokens: .max,
                    outputTokens: 1,
                    webSearchCount: 1
                )
        )
    }

    @Test("Saturated request totals cannot prove that a mixed day belongs to one client")
    func saturatedTotalsDoNotProveExclusivity() {
        var day = GatewayUsageDay(day: "2026-09-01")
        day.requests = .max
        day.failures = 1
        day.webSearchCount = 2
        day.clients = ["claude": Int.max - 1, "codex": 1]

        day.fold(event(outcome: .succeeded, client: .claude))

        #expect(day.clients["claude"] == .max)
        #expect(day.clientUsage["claude"]?.recordedRequests == 1)
        #expect(
            summary(of: day)
                == GatewayUsageSummary.DayDetail(
                    requests: .max,
                    failures: nil,
                    tokens: 0,
                    tokensAreEstimated: false,
                    webSearchCount: nil
                )
        )
    }

    @Test("Saturated recorded request counts cannot erase a gap in client attribution")
    func saturatedRecordsDoNotProveCompleteness() {
        var day = GatewayUsageDay(day: "2026-09-01")
        day.requests = .max
        day.failures = 1
        day.webSearchCount = 2
        day.clients = ["claude": .max, "codex": 1]
        day.clientUsage = ["claude": GatewayClientUsage(recordedRequests: Int.max - 1)]

        day.fold(event(outcome: .succeeded, client: .claude))

        #expect(day.clientUsage["claude"]?.recordedRequests == .max)
        #expect(
            summary(of: day)
                == GatewayUsageSummary.DayDetail(
                    requests: .max,
                    failures: nil,
                    tokens: 0,
                    tokensAreEstimated: false,
                    webSearchCount: nil
                )
        )
        day.failures = 0
        day.webSearchCount = 0
        #expect(summary(of: day).failures == 0)
        #expect(summary(of: day).webSearchCount == 0)
    }

    private func summary(of day: GatewayUsageDay) -> GatewayUsageSummary.DayDetail {
        GatewayUsageSummary(
            history: GatewayUsageHistory(days: [day]),
            client: .claude,
            now: date("2026-09-01T18:00:00Z"),
            calendar: utcCalendar
        ).today
    }

    private func legacyDay() -> GatewayUsageDay {
        var day = GatewayUsageDay(day: "2026-09-01")
        day.requests = 3
        day.failures = 1
        day.webSearchCount = 4
        day.clients = ["claude": 2, "codex": 1]
        day.clientUsage = [
            "claude": GatewayClientUsage(
                usage: GatewayUsageTotals(inputTokens: 8, outputTokens: 2, cacheReadTokens: 1, cacheWriteTokens: 3),
                estimatedTokens: 5
            )
        ]
        return day
    }
}
