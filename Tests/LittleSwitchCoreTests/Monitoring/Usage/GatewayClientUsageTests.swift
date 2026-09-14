import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Gateway client usage")
struct GatewayClientUsageTests {
    @Test("A failed request without tokens still records client attribution")
    func failureWithoutTokens() {
        var day = GatewayUsageDay(day: "2026-09-01")
        day.fold(event(outcome: .failed, client: .codex))

        #expect(day.clients == ["codex": 1])
        #expect(day.clientUsage["codex"] == GatewayClientUsage(recordedRequests: 1, failures: 1))
    }

    @Test("Reported client usage wins over the estimate and keeps web searches separate")
    func reportedUsageAndSearches() {
        var day = GatewayUsageDay(day: "2026-09-01")
        let usage = GatewayUsageTotals(inputTokens: 10, outputTokens: 3, cacheReadTokens: 2, cacheWriteTokens: 1)
        day.fold(
            GatewayUsageEvent(
                finishedAt: date("2026-09-01T12:00:00Z"),
                outcome: .succeeded,
                client: .claude,
                usage: usage,
                estimatedInputTokens: 900,
                toolSearchCount: 7,
                webSearchCount: 5
            )
        )

        #expect(
            day.clientUsage["claude"]
                == GatewayClientUsage(usage: usage, recordedRequests: 1, webSearchCount: 5)
        )
    }

    @Test("Empty reported client usage keeps the input estimate")
    func emptyReportedUsage() {
        var day = GatewayUsageDay(day: "2026-09-01")
        day.fold(
            event(
                outcome: .succeeded,
                client: .claude,
                usage: GatewayUsageTotals(),
                estimatedInputTokens: 12
            )
        )

        #expect(day.clientUsage["claude"] == GatewayClientUsage(estimatedTokens: 12, recordedRequests: 1))
    }

    @Test("A cancelled client request counts without becoming a failure")
    func cancelledRequest() {
        var day = GatewayUsageDay(day: "2026-09-01")
        day.fold(event(outcome: .cancelled, client: .codex))

        #expect(day.clientUsage["codex"] == GatewayClientUsage(recordedRequests: 1))
    }

    @Test("Legacy JSON keeps token usage with no recorded request counters")
    func legacyJSON() throws {
        let payload = Data(
            """
            {"usage":{"inputTokens":10,"outputTokens":4,"cacheReadTokens":3,"cacheWriteTokens":2},
             "estimatedTokens":5}
            """.utf8
        )

        let usage = try JSONDecoder().decode(GatewayClientUsage.self, from: payload)

        #expect(
            usage
                == GatewayClientUsage(
                    usage: GatewayUsageTotals(
                        inputTokens: 10,
                        outputTokens: 4,
                        cacheReadTokens: 3,
                        cacheWriteTokens: 2
                    ),
                    estimatedTokens: 5
                )
        )
        #expect(usage.recordedRequests == 0)
        #expect(usage.failures == 0)
        #expect(usage.webSearchCount == 0)
        #expect(usage.tokens == 24)
    }

    @Test("Client request and search counters survive a JSON round trip")
    func jsonRoundTrip() throws {
        let usage = GatewayClientUsage(
            usage: GatewayUsageTotals(inputTokens: 10, outputTokens: 4, cacheReadTokens: 3, cacheWriteTokens: 2),
            estimatedTokens: 5,
            recordedRequests: 3,
            failures: 1,
            webSearchCount: 6
        )

        let restored = try JSONDecoder().decode(GatewayClientUsage.self, from: JSONEncoder().encode(usage))

        #expect(restored == usage)
    }

    @Test("Client additions saturate every counter")
    func saturatedAddition() {
        let maximum = GatewayClientUsage(
            usage: GatewayUsageTotals(
                inputTokens: .max,
                outputTokens: .max,
                cacheReadTokens: .max,
                cacheWriteTokens: .max
            ),
            estimatedTokens: .max,
            recordedRequests: .max,
            failures: .max,
            webSearchCount: .max
        )
        let addition = GatewayClientUsage(
            usage: GatewayUsageTotals(inputTokens: 1, outputTokens: 1, cacheReadTokens: 1, cacheWriteTokens: 1),
            estimatedTokens: 1,
            recordedRequests: 1,
            failures: 1,
            webSearchCount: 1
        )

        #expect(maximum + addition == maximum)
        #expect(maximum.tokens == .max)
    }

    @Test("Negative client counters clamp to zero on creation and restoration")
    func nonnegativeCounters() throws {
        let payload = Data(
            """
            {"usage":{"inputTokens":0,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0},
             "estimatedTokens":-1,"recordedRequests":-2,"failures":-3,"webSearchCount":-4}
            """.utf8
        )

        #expect(
            GatewayClientUsage(estimatedTokens: -1, recordedRequests: -2, failures: -3, webSearchCount: -4)
                == GatewayClientUsage()
        )
        #expect(try JSONDecoder().decode(GatewayClientUsage.self, from: payload) == GatewayClientUsage())
    }

    @Test("Attribution stays bounded while existing client counters keep growing")
    func attributionKeyCap() {
        var day = GatewayUsageDay(day: "2026-09-01")
        day.clients = ["claude": 1]
        day.clientUsage = ["claude": GatewayClientUsage(recordedRequests: 1)]
        for index in 1..<GatewayUsageDay.clientKeyLimit {
            day.clients["client-\(index)"] = 1
            day.clientUsage["client-\(index)"] = GatewayClientUsage(recordedRequests: 1)
        }

        day.fold(event(outcome: .failed, client: .claude))
        day.fold(event(outcome: .failed, client: .codex))

        #expect(day.clients.count == GatewayUsageDay.clientKeyLimit)
        #expect(day.clientUsage.count == GatewayUsageDay.clientKeyLimit)
        #expect(day.clients["claude"] == 2)
        #expect(day.clientUsage["claude"] == GatewayClientUsage(recordedRequests: 2, failures: 1))
        #expect(day.clients["codex"] == nil)
        #expect(day.clientUsage["codex"] == nil)
    }
}
