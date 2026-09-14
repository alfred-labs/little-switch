import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Gateway usage history")
struct GatewayUsageHistoryTests {
    @Test("Totals clamp, saturate, add, and merge")
    func totalsArithmetic() {
        let clamped = GatewayUsageTotals(
            inputTokens: -5,
            outputTokens: 3,
            cacheReadTokens: -1,
            cacheWriteTokens: 2
        )

        #expect(clamped == GatewayUsageTotals(outputTokens: 3, cacheWriteTokens: 2))
        #expect(clamped.total == 5)
        #expect(!clamped.isEmpty)
        #expect(GatewayUsageTotals().isEmpty)
        #expect(GatewayUsageTotals(inputTokens: .max, outputTokens: 1).total == Int.max)
        #expect(
            GatewayUsageTotals(inputTokens: 1, outputTokens: 2)
                + GatewayUsageTotals(inputTokens: 3, cacheReadTokens: 4, cacheWriteTokens: 5)
                == GatewayUsageTotals(
                    inputTokens: 4,
                    outputTokens: 2,
                    cacheReadTokens: 4,
                    cacheWriteTokens: 5
                )
        )
        #expect(
            GatewayUsageTotals(inputTokens: 10, outputTokens: 2)
                .merging(GatewayUsageTotals(inputTokens: 1, outputTokens: 40, cacheReadTokens: 3))
                == GatewayUsageTotals(inputTokens: 10, outputTokens: 40, cacheReadTokens: 3)
        )
    }

    @Test("A histogram normalizes the buckets it is restored with")
    func histogramNormalization() {
        let padded = GatewayLatencyHistogram(buckets: [1, -2])
        let overlong = GatewayLatencyHistogram(
            buckets: Array(repeating: 1, count: GatewayLatencyHistogram.edges.count + 4)
        )

        #expect(padded.buckets.count == GatewayLatencyHistogram.edges.count + 1)
        #expect(padded.buckets[0] == 1)
        #expect(padded.buckets[1] == 0)
        #expect(padded.buckets.reduce(0, +) == 1)
        #expect(overlong.buckets.count == GatewayLatencyHistogram.edges.count + 1)
        #expect(overlong.buckets.reduce(0, +) == GatewayLatencyHistogram.edges.count + 1)
        #expect(GatewayLatencyHistogram().buckets.allSatisfy { $0 == 0 })
    }

    @Test("Samples land in the bucket that holds them")
    func histogramRecording() {
        var histogram = GatewayLatencyHistogram()
        histogram.record(milliseconds: 10)
        histogram.record(milliseconds: 50)
        histogram.record(milliseconds: 51)
        histogram.record(milliseconds: 900_000)

        #expect(histogram.buckets[0] == 2)
        #expect(histogram.buckets[1] == 1)
        #expect(histogram.buckets[GatewayLatencyHistogram.edges.count] == 1)
        #expect(histogram.buckets.reduce(0, +) == 4)
    }

    @Test("Merged histograms sum bucket by bucket")
    func histogramMerging() {
        var left = GatewayLatencyHistogram()
        left.record(milliseconds: 30)
        var right = GatewayLatencyHistogram()
        right.record(milliseconds: 30)
        right.record(milliseconds: 300)

        let merged = left.merging(right)

        #expect(merged.buckets[0] == 2)
        #expect(merged.buckets[3] == 1)
        #expect(merged.buckets.reduce(0, +) == 3)
    }

    @Test("A day counts outcomes, tokens, latency, and leaders")
    func dayFolding() {
        var day = GatewayUsageDay(day: "2026-09-01")
        day.fold(
            event(
                outcome: .succeeded,
                client: .claude,
                routeID: "claude-opus-5",
                providerName: "z.ai",
                modelID: "glm-4.7",
                durationMilliseconds: 1_200,
                usage: GatewayUsageTotals(inputTokens: 10, outputTokens: 5)
            )
        )
        day.fold(
            event(
                outcome: .failed,
                client: .codex,
                routeID: "claude-opus-5",
                providerName: "z.ai",
                modelID: "glm-4.7",
                durationMilliseconds: 90_000,
                estimatedInputTokens: 400
            )
        )
        day.fold(event(outcome: .cancelled, client: .codex))

        #expect(day.requests == 3)
        #expect(day.failures == 1)
        #expect(day.cancellations == 1)
        #expect(day.usage == GatewayUsageTotals(inputTokens: 10, outputTokens: 5))
        #expect(day.reportedUsageRequests == 1)
        #expect(day.estimatedTokens == 400)
        #expect(day.tokens == 415)
        #expect(day.usesEstimatedTokens)
        #expect(day.latency.buckets.reduce(0, +) == 1)
        #expect(day.clients == ["claude": 1, "codex": 2])
        #expect(day.clientUsage.count == 2)
        #expect(
            day.clientUsage["claude"]?.usage
                == GatewayUsageTotals(inputTokens: 10, outputTokens: 5)
        )
        #expect(day.clientUsage["claude"]?.tokens == 15)
        #expect(day.clientUsage["claude"]?.recordedRequests == 1)
        #expect(day.clientUsage["claude"]?.failures == 0)
        #expect(day.clientUsage["codex"]?.usage.isEmpty == true)
        #expect(day.clientUsage["codex"]?.estimatedTokens == 400)
        #expect(day.clientUsage["codex"]?.tokens == 400)
        #expect(day.clientUsage["codex"]?.recordedRequests == 2)
        #expect(day.clientUsage["codex"]?.failures == 1)
        #expect(day.targets.count == 1)
        #expect(day.targets.values.first == 2)
    }

    @Test("Web search calls ride a finished traffic event into the day")
    func webSearchCountFolding() throws {
        let startedAt = date("2026-09-01T10:00:00Z")
        var traffic = TrafficEvent(
            firstRecord: TrafficRecord(
                eventID: UUID(),
                sequence: 0,
                timestamp: startedAt,
                action: .cancelled(finishedAt: startedAt)
            )
        )
        traffic.path = "/v1/messages"
        traffic.lifecycle = .completed
        traffic.finishedAt = startedAt.addingTimeInterval(60)
        traffic.webSearches = [
            TrafficWebSearch(
                provider: "firecrawl",
                query: "swift structured concurrency",
                startedAt: startedAt,
                finishedAt: startedAt.addingTimeInterval(2),
                resultCount: 5,
                failure: nil
            ),
            TrafficWebSearch(
                provider: "firecrawl",
                query: "grand central dispatch",
                startedAt: startedAt,
                finishedAt: startedAt.addingTimeInterval(1),
                resultCount: nil,
                failure: TrafficFailure(kind: "web-search", message: "timed out")
            ),
        ]

        let usageEvent = GatewayUsageEvent(trafficEvent: traffic)
        #expect(usageEvent?.webSearchCount == 2)

        var day = GatewayUsageDay(day: "2026-09-01")
        day.fold(try #require(usageEvent))
        #expect(day.webSearchCount == 2)
        #expect(day.toolSearchCount == 0)
    }

    @Test("A request that resolved nothing counts without a target")
    func dayFoldingWithoutTarget() {
        var day = GatewayUsageDay(day: "2026-09-01")
        day.fold(event(outcome: .failed))

        #expect(day.requests == 1)
        #expect(day.targets.isEmpty)
        #expect(day.clients.isEmpty)
        #expect(day.clientUsage.isEmpty)
        #expect(day.tokens == 0)
        #expect(!day.usesEstimatedTokens)
    }

    @Test("Empty usage falls back to the estimate")
    func dayFoldingPrefersReportedUsage() {
        var day = GatewayUsageDay(day: "2026-09-01")
        day.fold(event(outcome: .succeeded, usage: GatewayUsageTotals(), estimatedInputTokens: 12))
        day.fold(event(outcome: .succeeded, estimatedInputTokens: 0))

        #expect(day.estimatedTokens == 12)
        #expect(day.reportedUsageRequests == 0)
    }

    @Test("Target and client keys stop growing at their caps")
    func dayKeyCaps() {
        var day = GatewayUsageDay(day: "2026-09-01")
        for index in 0...GatewayUsageDay.targetKeyLimit {
            day.fold(event(outcome: .succeeded, routeID: "route-\(index)"))
        }

        #expect(day.targets.count == GatewayUsageDay.targetKeyLimit)
        #expect(day.requests == GatewayUsageDay.targetKeyLimit + 1)
    }

    @Test("A target key preserves complete and partial routing identities")
    func targetKeys() {
        let full = event(
            outcome: .succeeded,
            routeID: "claude-opus-5",
            providerName: "z.ai",
            modelID: "glm-4.7"
        )
        let partial = event(outcome: .succeeded, providerName: "ollama")
        #expect(full.targetKey == "claude-opus-5\u{001F}z.ai\u{001F}glm-4.7")
        #expect(partial.targetKey == "\u{001F}ollama\u{001F}")
        #expect(event(outcome: .succeeded).targetKey.isEmpty)
    }

    @Test("Folding groups by local day and keeps the retention window")
    func historyFolding() {
        var history = GatewayUsageHistory()
        let start = date("2026-07-01T09:00:00Z")
        for offset in 0..<(GatewayUsageHistory.retainedDays + 3) {
            guard let day = utcCalendar.date(byAdding: .day, value: offset, to: start) else {
                continue
            }
            history.fold(event(finishedAt: day, outcome: .succeeded), calendar: utcCalendar)
        }
        history.fold(event(finishedAt: start, outcome: .succeeded), calendar: utcCalendar)

        #expect(history.days.count == GatewayUsageHistory.retainedDays)
        #expect(history.days.first?.day == "2026-07-04")
        #expect(history.day("2026-07-01") == nil)
        #expect(history.day("2026-07-04")?.requests == 1)
    }

    @Test("Repeated folds land in the same day")
    func historyFoldingSameDay() {
        var history = GatewayUsageHistory()
        let moment = date("2026-09-01T10:00:00Z")
        history.fold(event(finishedAt: moment, outcome: .succeeded), calendar: utcCalendar)
        history.fold(event(finishedAt: moment, outcome: .failed), calendar: utcCalendar)

        #expect(history.days.count == 1)
        #expect(history.day("2026-09-01")?.requests == 2)
        #expect(history.day("2026-09-01")?.failures == 1)
    }

    @Test("A restored history is sorted and trimmed")
    func historyRestoration() {
        let keys = GatewayUsageHistory.dayKeys(
            endingAt: date("2026-08-01T12:00:00Z"),
            count: GatewayUsageHistory.retainedDays + 2,
            calendar: utcCalendar
        )

        let history = GatewayUsageHistory(days: keys.reversed().map { GatewayUsageDay(day: $0) })

        #expect(history.days.count == GatewayUsageHistory.retainedDays)
        #expect(history.days.first?.day == "2026-07-03")
        #expect(history.days.last?.day == "2026-08-01")
    }

    @Test("Day keys run oldest first and stop at zero")
    func dayKeySeries() {
        let keys = GatewayUsageHistory.dayKeys(
            endingAt: date("2026-09-01T23:30:00Z"),
            count: 3,
            calendar: utcCalendar
        )

        #expect(keys == ["2026-08-30", "2026-08-31", "2026-09-01"])
        #expect(
            GatewayUsageHistory.dayKeys(
                endingAt: date("2026-09-01T23:30:00Z"),
                count: -1,
                calendar: utcCalendar
            ).isEmpty
        )
    }
}

func event(
    finishedAt: Date = Date(timeIntervalSince1970: 1_788_000_000),
    outcome: GatewayUsageEvent.Outcome,
    client: GatewayClient? = nil,
    routeID: String? = nil,
    providerName: String? = nil,
    modelID: String? = nil,
    durationMilliseconds: Int? = nil,
    usage: GatewayUsageTotals? = nil,
    estimatedInputTokens: Int? = nil
) -> GatewayUsageEvent {
    GatewayUsageEvent(
        finishedAt: finishedAt,
        outcome: outcome,
        client: client,
        routeID: routeID,
        providerName: providerName,
        modelID: modelID,
        durationMilliseconds: durationMilliseconds,
        usage: usage,
        estimatedInputTokens: estimatedInputTokens
    )
}

var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}

func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso) ?? Date(timeIntervalSince1970: 0)
}
