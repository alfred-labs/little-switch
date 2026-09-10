import Foundation
import GRDB
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

/// The usage-day schema is append-only: every migration must open a database
/// written by the previous version and keep its rows readable.
@Suite("Gateway usage history migration")
struct GatewayUsageHistoryMigrationTests {
    @Test("A database from the previous schema version upgrades in place")
    func v1DatabaseMigratesInPlace() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let dayKey = GatewayUsageHistory.dayKey(for: now, calendar: storeCalendar)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await DatabaseQueue(path: fileURL.path).write { database in
            try database.execute(
                sql: """
                    CREATE TABLE usageDay (
                        day TEXT PRIMARY KEY NOT NULL,
                        requests INTEGER NOT NULL DEFAULT 0,
                        failures INTEGER NOT NULL DEFAULT 0,
                        cancellations INTEGER NOT NULL DEFAULT 0,
                        inputTokens INTEGER NOT NULL DEFAULT 0,
                        outputTokens INTEGER NOT NULL DEFAULT 0,
                        cacheReadTokens INTEGER NOT NULL DEFAULT 0,
                        cacheWriteTokens INTEGER NOT NULL DEFAULT 0,
                        estimatedTokens INTEGER NOT NULL DEFAULT 0,
                        reportedUsageRequests INTEGER NOT NULL DEFAULT 0,
                        latencyBuckets TEXT NOT NULL DEFAULT '[]',
                        targets TEXT NOT NULL DEFAULT '{}',
                        clients TEXT NOT NULL DEFAULT '{}'
                    )
                    """
            )
            try database.execute(
                sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)"
            )
            try database.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                arguments: ["v1-create-usage-day"]
            )
            try database.execute(
                sql: """
                    INSERT INTO usageDay (
                        day, requests, failures, inputTokens, outputTokens,
                        latencyBuckets, targets, clients
                    ) VALUES (?, 3, 1, 100, 20, '[0, 0, 1]', '{}', '{"claude": 3}')
                    """,
                arguments: [dayKey]
            )
        }

        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        // The v1 row survives the upgrade with its counters intact.
        #expect(await store.summary(now: now).today.requests == 3)
        #expect(await store.summary(now: now).today.tokens == 120)
        // It carries no per-client split: requests read, tokens do not.
        let clients = await store.clientSummaries(now: now)
        #expect(clients[.claude]?.today.requests == 3)
        #expect(clients[.claude]?.today.tokens == 0)
        await store.stop()

        await store.fold(
            GatewayUsageEvent(
                finishedAt: now,
                outcome: .succeeded,
                client: .claude,
                usage: GatewayUsageTotals(inputTokens: 7)
            )
        )
        await store.stop()

        let restored = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        #expect(await restored.summary(now: now).today.requests == 4)
        let restoredClients = await restored.clientSummaries(now: now)
        #expect(restoredClients[.claude]?.today.requests == 4)
        #expect(restoredClients[.claude]?.today.tokens == 7)
        await restored.stop()
    }

    private var storeCalendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return value
    }

    private func temporaryFileURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-history-migration-\(UUID().uuidString)")
        return directory.appendingPathComponent("usage-history.sqlite")
    }
}
