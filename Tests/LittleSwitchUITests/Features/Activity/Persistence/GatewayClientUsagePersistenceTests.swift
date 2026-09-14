import Foundation
import GRDB
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Filtered client usage persistence")
struct GatewayClientUsagePersistenceTests {
    @Test("The complete six-insight client totals survive SQLite persistence")
    func completeCountsPersist() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = GatewayUsageHistoryStore(configuration: .init(fileURL: fileURL), calendar: calendar)
        await store.fold(
            GatewayUsageEvent(
                finishedAt: now,
                outcome: .succeeded,
                client: .claude,
                usage: GatewayUsageTotals(
                    inputTokens: 100, outputTokens: 20, cacheReadTokens: 30, cacheWriteTokens: 40),
                webSearchCount: 2
            )
        )
        await store.fold(
            GatewayUsageEvent(finishedAt: now, outcome: .failed, client: .claude, estimatedInputTokens: 10)
        )
        await store.fold(GatewayUsageEvent(finishedAt: now, outcome: .failed, client: .codex, webSearchCount: 3))
        await store.fold(GatewayUsageEvent(finishedAt: now, outcome: .cancelled, client: .codex))
        await store.stop()

        let restored = GatewayUsageHistoryStore(configuration: .init(fileURL: fileURL), calendar: calendar)
        let summaries = await restored.clientSummaries(now: now)
        #expect(
            summaries[.claude]?.today
                == GatewayUsageSummary.DayDetail(
                    requests: 2,
                    failures: 1,
                    tokens: 200,
                    tokensAreEstimated: true,
                    inputTokens: 110,
                    cachedTokens: 70,
                    outputTokens: 20,
                    webSearchCount: 2
                )
        )
        #expect(
            summaries[.codex]?.today
                == GatewayUsageSummary.DayDetail(
                    requests: 2, failures: 1, tokens: 0, tokensAreEstimated: false, webSearchCount: 3
                )
        )
        let current = await store.clientSummaries(now: now)
        #expect(summaries == current)
        await restored.stop()
    }

    @Test("Old client JSON retains its tokens and unknown counts after a new request and relaunch")
    func oldPayloadRemainsReadable() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let database = try #require(GatewayUsageHistoryDatabase.opening(fileURL: fileURL))
        var day = GatewayUsageDay(day: GatewayUsageHistory.dayKey(for: now, calendar: calendar))
        day.requests = 10
        day.failures = 2
        day.webSearchCount = 5
        day.clients = ["claude": 4, "codex": 6]
        try database.writeDays([day])
        let oldPayload = """
            {"claude":{"usage":{"inputTokens":100,"outputTokens":20,"cacheReadTokens":5,"cacheWriteTokens":2},"estimatedTokens":10}}
            """
        try await DatabaseQueue(path: fileURL.path).write { database in
            try database.execute(sql: "UPDATE usageDay SET clientUsage = ?", arguments: [oldPayload])
        }

        let store = GatewayUsageHistoryStore(configuration: .init(fileURL: fileURL), calendar: calendar)
        let old = try #require(await store.clientSummaries(now: now)[.claude])
        #expect(old.today.requests == 4)
        #expect(old.today.tokens == 137)
        #expect(old.today.failures == nil)
        #expect(old.today.webSearchCount == nil)
        await store.fold(
            GatewayUsageEvent(
                finishedAt: now,
                outcome: .failed,
                client: .claude,
                usage: GatewayUsageTotals(inputTokens: 7),
                webSearchCount: 2
            )
        )
        await store.stop()
        let restored = GatewayUsageHistoryStore(configuration: .init(fileURL: fileURL), calendar: calendar)
        let summary = try #require(await restored.clientSummaries(now: now)[.claude])
        #expect(
            summary.today
                == GatewayUsageSummary.DayDetail(
                    requests: 5,
                    failures: nil,
                    tokens: 144,
                    tokensAreEstimated: true,
                    inputTokens: 117,
                    cachedTokens: 7,
                    outputTokens: 20,
                    webSearchCount: nil
                )
        )
        #expect(try database.readDays().count == 1)
        await restored.stop()
    }

    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("client-insights-\(UUID().uuidString)")
            .appendingPathComponent("usage-history.sqlite")
    }
}
