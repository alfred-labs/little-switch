import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Gateway client insights presentation")
struct GatewayClientInsightsPresentationTests {
    @Test("A quiet client has six zero insights and the same thirty-day geometry")
    func quietClient() {
        let stats = presentation(client: .claude, days: [])
        #expect(stats.period(at: nil).metrics.map(\.value) == ["0", "0", "0", "0", "0%", "0"])
        #expect(stats.period(at: nil).tokenTotal == "0")
        #expect(stats.points == Array(repeating: 0, count: 30))
        #expect(stats.axisLabels == ["Jul 31", "Aug 14", "Aug 29"])
    }

    @Test("The six insights aggregate only the chosen client's traffic")
    func clientIsolation() {
        let claude = presentation(client: .claude, days: busyDays).period(at: nil)
        let codex = presentation(client: .codex, days: busyDays).period(at: nil)

        #expect(
            claude.metrics.map(\.title)
                == ["Input tokens (est.)", "Cached tokens", "Output tokens", "Requests", "Errors", "Web searches"]
        )
        #expect(claude.metrics.map(\.value) == ["1.2K", "65", "120", "5", "20%", "3"])
        #expect(claude.tokenTotal == "1.42K")
        #expect(claude.accessibilityValue.hasSuffix("includes estimates"))
        #expect(codex.metrics.map(\.value) == ["18K", "9K", "1.8K", "10", "50%", "12"])
        #expect(codex.tokenTotal == "28.8K")
        #expect(codex.metrics[0].title == "Input tokens")
    }

    @Test("Inspecting a day changes the headline and all six filtered insights together")
    func selectedPeriod() {
        let stats = presentation(client: .claude, days: busyDays)
        let yesterday = stats.period(at: 28)
        let today = stats.period(at: 29)

        #expect(yesterday.label == "Aug 28")
        #expect(yesterday.tokenTotal == "1.15K")
        #expect(yesterday.metrics.map(\.value) == ["1K", "50", "100", "4", "25%", "2"])
        #expect(yesterday.metrics[0].title == "Input tokens")
        #expect(today.label == "Today")
        #expect(today.tokenTotal == "275")
        #expect(today.metrics.map(\.value) == ["240", "15", "20", "1", "0%", "1"])
        #expect(today.metrics[0].title == "Input tokens (est.)")
        #expect(stats.period(at: nil).metrics.map(\.value) == ["1.2K", "65", "120", "5", "20%", "3"])
        #expect(today.accessibilityValue == "Today, 275 tokens, includes estimates")
        #expect(stats.period(at: Int.min) == stats.period(at: 0))
        #expect(stats.period(at: Int.max) == today)
    }

    @Test("Traffic outside the thirty-day window is excluded for either client")
    func boundedPeriod() {
        var old = busyDays[0]
        old.day = "2026-07-30"
        for client in [GatewayClient.claude, .codex] {
            #expect(
                presentation(client: client, days: [old] + busyDays)
                    == presentation(client: client, days: busyDays)
            )
        }
    }

    @Test("Legacy mixed traffic shows unavailable counts without hiding the existing tokens")
    func unavailableHistory() {
        let stats = presentation(client: .claude, days: [legacyDay, busyDays[1]])
        let period = stats.period(at: nil)
        #expect(period.metrics.map(\.value) == ["250", "15", "20", "3", "—", "—"])
        #expect(period.metrics[4].accessibilityValue == "Unavailable for this period")
        #expect(period.metrics[5].accessibilityValue == "Unavailable for this period")
        #expect(period.metrics[3].accessibilityValue == "3")
        #expect(stats.period(at: 28).metrics.map(\.value) == ["10", "0", "0", "2", "—", "—"])
        #expect(stats.period(at: 29).metrics.map(\.value) == ["240", "15", "20", "1", "0%", "1"])
    }

    @Test("Historical zero errors and zero searches remain independently provable")
    func independentAvailability() {
        var noErrors = legacyDay
        noErrors.failures = 0
        var noSearches = legacyDay
        noSearches.webSearchCount = 0
        #expect(
            presentation(client: .claude, days: [noErrors]).period(at: nil).metrics.suffix(2).map(\.value)
                == ["0%", "—"]
        )
        #expect(
            presentation(client: .claude, days: [noSearches]).period(at: nil).metrics.suffix(2).map(\.value)
                == ["—", "0"]
        )
    }

    private func presentation(client: GatewayClient, days: [GatewayUsageDay]) -> GatewayUsageStatsPresentation {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return GatewayUsageStatsPresentation(
            summary: GatewayUsageSummary(
                history: GatewayUsageHistory(days: days),
                client: client,
                now: Date(timeIntervalSince1970: 1_788_000_000),
                calendar: calendar
            )
        )
    }

    private var busyDays: [GatewayUsageDay] {
        [
            day(
                "2026-08-28",
                claude: GatewayClientUsage(
                    usage: GatewayUsageTotals(
                        inputTokens: 1_000, outputTokens: 100, cacheReadTokens: 20, cacheWriteTokens: 30),
                    recordedRequests: 4,
                    failures: 1,
                    webSearchCount: 2
                ),
                codex: GatewayClientUsage(
                    usage: GatewayUsageTotals(
                        inputTokens: 8_000, outputTokens: 800, cacheReadTokens: 1_600, cacheWriteTokens: 2_400),
                    recordedRequests: 8,
                    failures: 4,
                    webSearchCount: 9
                )
            ),
            day(
                "2026-08-29",
                claude: GatewayClientUsage(
                    usage: GatewayUsageTotals(
                        inputTokens: 200, outputTokens: 20, cacheReadTokens: 5, cacheWriteTokens: 10),
                    estimatedTokens: 40,
                    recordedRequests: 1,
                    failures: 0,
                    webSearchCount: 1
                ),
                codex: GatewayClientUsage(
                    usage: GatewayUsageTotals(
                        inputTokens: 10_000, outputTokens: 1_000, cacheReadTokens: 2_000, cacheWriteTokens: 3_000),
                    recordedRequests: 2,
                    failures: 1,
                    webSearchCount: 3
                )
            ),
        ]
    }

    private var legacyDay: GatewayUsageDay {
        var day = GatewayUsageDay(day: "2026-08-28")
        day.requests = 4
        day.failures = 1
        day.webSearchCount = 2
        day.clients = ["claude": 2, "codex": 2]
        day.clientUsage = ["claude": GatewayClientUsage(usage: GatewayUsageTotals(inputTokens: 10))]
        return day
    }

    private func day(_ key: String, claude: GatewayClientUsage, codex: GatewayClientUsage) -> GatewayUsageDay {
        var day = GatewayUsageDay(day: key)
        day.requests = claude.recordedRequests + codex.recordedRequests
        day.failures = claude.failures + codex.failures
        day.webSearchCount = claude.webSearchCount + codex.webSearchCount
        day.clients = ["claude": claude.recordedRequests, "codex": codex.recordedRequests]
        day.clientUsage = ["claude": claude, "codex": codex]
        day.usage = claude.usage + codex.usage
        day.estimatedTokens = claude.estimatedTokens + codex.estimatedTokens
        return day
    }
}
