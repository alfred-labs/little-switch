import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Gateway usage summary")
struct GatewayUsageSummaryTests {
    @Test("An empty history summarizes to a flat, empty series")
    func emptyHistory() {
        let summary = GatewayUsageSummary(
            history: GatewayUsageHistory(),
            now: date("2026-09-01T12:00:00Z"),
            calendar: utcCalendar
        )

        #expect(summary.points.count == GatewayUsageSummary.seriesDays)
        #expect(summary.points.last?.day == "2026-09-01")
        #expect(summary.points.allSatisfy { $0.tokens == 0 })
        #expect(summary.today.requests == 0)
        #expect(summary.today.failures == 0)
        #expect(summary.today.tokens == 0)
        #expect(summary.today.tokensAreEstimated == false)
        #expect(summary.dayDetails == Array(repeating: .empty, count: GatewayUsageSummary.seriesDays))
    }

    @Test("Today and every series day read from the same history")
    func populatedHistory() {
        var history = GatewayUsageHistory()
        let now = date("2026-09-01T18:00:00Z")
        // Older requests retain their own day in the thirty-day series.
        history.fold(
            event(finishedAt: date("2026-08-23T10:00:00Z"), outcome: .succeeded),
            calendar: utcCalendar
        )
        history.fold(
            event(finishedAt: date("2026-08-28T10:00:00Z"), outcome: .succeeded),
            calendar: utcCalendar
        )
        for _ in 0..<3 {
            history.fold(
                event(
                    finishedAt: now,
                    outcome: .succeeded,
                    client: .claude,
                    routeID: "claude-opus-5",
                    providerName: "z.ai",
                    modelID: "glm-4.7",
                    durationMilliseconds: 900,
                    usage: GatewayUsageTotals(inputTokens: 100, outputTokens: 20)
                ),
                calendar: utcCalendar
            )
        }
        history.fold(
            event(
                finishedAt: now,
                outcome: .failed,
                client: .codex,
                routeID: "claude-sonnet-5",
                providerName: "ollama",
                durationMilliseconds: 30_000
            ),
            calendar: utcCalendar
        )

        let summary = GatewayUsageSummary(history: history, now: now, calendar: utcCalendar)

        #expect(summary.today.requests == 4)
        #expect(summary.today.failures == 1)
        #expect(summary.today.tokens == 360)
        #expect(summary.today.tokensAreEstimated == false)
        let requestsByDay = ["2026-08-23": 1, "2026-08-28": 1, "2026-09-01": 4]
        #expect(
            summary.dayDetails.map(\.requests)
                == summary.points.map { requestsByDay[$0.day, default: 0] }
        )
        #expect(summary.points.count == GatewayUsageSummary.seriesDays)
        #expect(
            summary.points.last
                == GatewayUsageSummary.Point(day: "2026-09-01", tokens: 360)
        )
        #expect(
            summary.points.first
                == GatewayUsageSummary.Point(day: "2026-08-03", tokens: 0)
        )
        #expect(summary.points.map(\.tokens).reduce(0, +) == 360)
        #expect(summary.points.contains { $0.tokens > 0 })
    }

    @Test("Estimated tokens are reported as such")
    func estimatedTokens() {
        var history = GatewayUsageHistory()
        let now = date("2026-09-01T18:00:00Z")
        history.fold(
            event(finishedAt: now, outcome: .succeeded, estimatedInputTokens: 750),
            calendar: utcCalendar
        )

        let summary = GatewayUsageSummary(history: history, now: now, calendar: utcCalendar)

        #expect(summary.today.tokens == 750)
        #expect(summary.today.tokensAreEstimated == true)
    }

    @Test("Every series day carries its own detail for the menu's hover block")
    func dayDetails() throws {
        var history = GatewayUsageHistory()
        let now = date("2026-09-01T18:00:00Z")
        let yesterday = date("2026-08-31T10:00:00Z")
        for _ in 0..<2 {
            history.fold(
                event(
                    finishedAt: yesterday,
                    outcome: .succeeded,
                    client: .claude,
                    routeID: "claude-opus-5",
                    providerName: "z.ai",
                    modelID: "glm-4.7",
                    durationMilliseconds: 900,
                    usage: GatewayUsageTotals(inputTokens: 500, outputTokens: 100)
                ),
                calendar: utcCalendar
            )
        }
        history.fold(
            event(
                finishedAt: now,
                outcome: .failed,
                client: .codex,
                routeID: "claude-sonnet-5",
                providerName: "ollama",
                durationMilliseconds: 30_000
            ),
            calendar: utcCalendar
        )

        let summary = GatewayUsageSummary(history: history, now: now, calendar: utcCalendar)

        #expect(summary.dayDetails.count == GatewayUsageSummary.seriesDays)
        #expect(summary.dayDetails.count == summary.points.count)
        // The empty days read as zeroed placeholders, so the hover block never
        // renders a hole.
        let empty = try #require(summary.dayDetails.first)
        #expect(empty.requests == 0)
        #expect(empty.failures == 0)
        #expect(empty.tokens == 0)
        #expect(empty == .empty)
        // Yesterday's day, one series slot before today.
        let previous = summary.dayDetails[summary.dayDetails.count - 2]
        #expect(previous.requests == 2)
        #expect(previous.failures == 0)
        #expect(previous.tokens == 1_200)
        #expect(previous.inputTokens == 1_000)
        #expect(previous.outputTokens == 200)
        // Today mirrors the headline counters.
        let today = try #require(summary.dayDetails.last)
        #expect(today.requests == 1)
        #expect(today.failures == 1)
        #expect(today == summary.today)
    }
}
