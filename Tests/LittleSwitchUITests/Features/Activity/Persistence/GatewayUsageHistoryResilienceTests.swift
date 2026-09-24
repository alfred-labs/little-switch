import Foundation
import GRDB
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

/// The database's failure and retention behavior: corruption-only rebuilds,
/// retention pruning, and flush retries that keep the counters durable
/// without a cooperating caller.
@Suite("Gateway usage history resilience")
struct GatewayUsageHistoryResilienceTests {

    @Test("An open failure that is not corruption keeps the file on disk")
    func transientOpenFailureKeepsFile() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let seeding = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        await seeding.fold(GatewayUsageEvent(finishedAt: now, outcome: .succeeded, client: .claude))
        await seeding.stop()

        // Losing the migration ledger replays v1 into an existing table: a
        // generic open-time failure on an undamaged database. Nuking the
        // file over it would erase a healthy history; the store must fall
        // back to memory and leave the disk alone.
        try await DatabaseQueue(path: fileURL.path).write { database in
            try database.execute(sql: "DROP TABLE grdb_migrations")
        }

        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        #expect(await store.summary(now: now).today.requests == 0)
        await store.stop()

        let stored = try await DatabaseQueue(path: fileURL.path).read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT requests FROM usageDay WHERE day = ?",
                arguments: [GatewayUsageHistory.dayKey(for: now, calendar: storeCalendar)]
            )
        }
        #expect(stored == 1)
    }

    @Test("Days older than the retention window are deleted from disk")
    func expiredDaysArePrunedOnLoad() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        await store.fold(GatewayUsageEvent(finishedAt: now, outcome: .succeeded, client: .claude))
        await store.stop()

        // A row predating the window — the kind older builds accumulate one
        // per day — must not survive the next open.
        try await DatabaseQueue(path: fileURL.path).write { database in
            try database.execute(sql: "INSERT INTO usageDay (day) VALUES ('2020-01-01')")
        }

        let pruned = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        _ = await pruned.summary(now: now)
        await pruned.stop()

        let strays = try await DatabaseQueue(path: fileURL.path).read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM usageDay WHERE day < '2026-01-01'"
            )
        }
        #expect(strays == 0)
    }

    @Test("A failed flush retries on its own, even with no further request")
    func failedFlushRetries() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let key = GatewayUsageHistory.dayKey(for: now, calendar: storeCalendar)
        let seeding = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        await seeding.fold(GatewayUsageEvent(finishedAt: now, outcome: .succeeded, client: .claude))
        await seeding.stop()

        // Hide the table after the schema exists: the next store loads with
        // its day in memory (the read fails into a fresh history), and every
        // flush write fails until the table returns.
        let fixtureQueue = try retryFixtureQueue(fileURL: fileURL)
        try await fixtureQueue.write { database in
            try database.execute(sql: "ALTER TABLE usageDay RENAME TO usageDayHidden")
        }

        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL, flushInterval: .milliseconds(50)),
            calendar: storeCalendar
        )
        // Three folds give the store's in-memory day a value only its own
        // flush can write: the hidden table's read failed, so nothing else
        // carries these deltas.
        for _ in 0..<3 {
            await store.fold(GatewayUsageEvent(finishedAt: now, outcome: .succeeded, client: .codex))
        }
        try await Task.sleep(for: .milliseconds(150))
        let hidden = try await fixtureQueue.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT requests FROM usageDayHidden WHERE day = ?",
                arguments: [key]
            )
        }
        #expect(hidden == 1)

        // Restore the table and wait for the store's own retry to land the
        // pending delta — nothing else folds, so only the re-armed flush can.
        try await fixtureQueue.write { database in
            try database.execute(sql: "ALTER TABLE usageDayHidden RENAME TO usageDay")
        }
        try await Task.sleep(for: .milliseconds(400))

        let stored = try await fixtureQueue.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT requests FROM usageDay WHERE day = ?",
                arguments: [key]
            )
        }
        #expect(stored == 3)
        await store.stop()
    }

    @Test("A synchronous store's failed flush retries on the default delay")
    func synchronousFailedFlushRetries() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let key = GatewayUsageHistory.dayKey(for: now, calendar: storeCalendar)
        let seeding = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        await seeding.fold(GatewayUsageEvent(finishedAt: now, outcome: .succeeded, client: .claude))
        await seeding.stop()

        let fixtureQueue = try retryFixtureQueue(fileURL: fileURL)
        try await fixtureQueue.write { database in
            try database.execute(sql: "ALTER TABLE usageDay RENAME TO usageDayHidden")
        }

        // No flush interval: every fold flushes synchronously, fails, and
        // must fall back to the retry's own default delay.
        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        for _ in 0..<3 {
            await store.fold(GatewayUsageEvent(finishedAt: now, outcome: .succeeded, client: .codex))
        }

        try await fixtureQueue.write { database in
            try database.execute(sql: "ALTER TABLE usageDayHidden RENAME TO usageDay")
        }
        try await Task.sleep(for: .milliseconds(2_400))

        let stored = try await fixtureQueue.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT requests FROM usageDay WHERE day = ?",
                arguments: [key]
            )
        }
        #expect(stored == 3)
        await store.stop()
    }

    private func retryFixtureQueue(fileURL: URL) throws -> DatabaseQueue {
        var configuration = Configuration()
        // Restoring the table can overlap the store's autonomous retry.
        // Bound fixture lock waiting without masking the missing-table failure.
        configuration.busyMode = .timeout(5)
        return try DatabaseQueue(path: fileURL.path, configuration: configuration)
    }
}
