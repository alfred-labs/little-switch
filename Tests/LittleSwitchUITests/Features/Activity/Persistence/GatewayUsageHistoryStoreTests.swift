import Foundation
import GRDB
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Gateway usage history store")
struct GatewayUsageHistoryStoreTests {
    @Test("Recorded requests survive a restart")
    func recordedRequestsPersist() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )

        await store.start()
        await store.start()
        let recordedEvent = GatewayUsageEvent(
            finishedAt: now,
            outcome: .succeeded,
            client: .claude,
            routeID: "claude-opus-5",
            providerName: "z.ai",
            modelID: "glm-4.7",
            durationMilliseconds: 900,
            usage: GatewayUsageTotals(inputTokens: 100, outputTokens: 20)
        )
        store.record(recordedEvent)
        await store.stop()

        // The menu no longer projects targets or latency. Assert the complete
        // persisted day so those durable aggregates remain covered too.
        var expectedDay = GatewayUsageDay(
            day: GatewayUsageHistory.dayKey(for: now, calendar: storeCalendar)
        )
        expectedDay.fold(recordedEvent)
        let database = try #require(GatewayUsageHistoryDatabase.opening(fileURL: fileURL))
        #expect(try database.readDays() == [expectedDay])

        let summary = await store.summary(now: now)
        #expect(summary.today.requests == 1)
        #expect(summary.today.tokens == 120)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let restored = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        let restoredSummary = await restored.summary(now: now)

        #expect(restoredSummary == summary)
        #expect(restoredSummary.today.requests == 1)
        // The filtered summary uses the same day identity as the full history.
        let summaries = await restored.clientSummaries(now: now)
        #expect(summaries[.claude]?.today.requests == 1)
        #expect(summaries[.claude]?.today.tokens == 120)
        #expect(summaries[.claude]?.points.last == restoredSummary.points.last)
    }

    @Test("Folding a request updates the summary immediately")
    func foldingUpdatesSummary() async {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )

        await store.fold(
            GatewayUsageEvent(finishedAt: now, outcome: .failed, estimatedInputTokens: 40)
        )
        await store.stop()

        let summary = await store.summary(now: now)
        #expect(summary.today.requests == 1)
        #expect(summary.today.failures == 1)
        #expect(summary.today.tokens == 40)
        #expect(summary.today.tokensAreEstimated == true)
    }

    @Test("A store with no history behind it starts empty")
    func missingFileStartsEmpty() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )

        #expect(await store.summary(now: now).today.requests == 0)
    }

    @Test("Flushes coalesce until the interval elapses")
    func deferredFlush() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL, flushInterval: .milliseconds(150)),
            calendar: storeCalendar
        )

        await store.start()
        await store.fold(GatewayUsageEvent(finishedAt: now, outcome: .succeeded))
        await store.fold(GatewayUsageEvent(finishedAt: now, outcome: .failed))

        let liveSummary = await store.summary(now: now)
        #expect(liveSummary.today.requests == 2)

        // Nothing reached the database before the interval elapsed.
        let early = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        #expect(await early.summary(now: now).today.requests == 0)

        do {
            let afterSummary: GatewayUsageSummary = try await eventually(description: "automatic usage-history flush") {
                // Each probe must reopen the database: a store caches its first read.
                let after = GatewayUsageHistoryStore(
                    configuration: .init(fileURL: fileURL),
                    calendar: storeCalendar
                )
                let summary = await after.summary(now: now)
                guard summary.today.requests > 0 else {
                    try await Task.sleep(for: .milliseconds(10))
                    return nil
                }
                return summary
            }
            #expect(afterSummary.today.requests == 2)
            #expect(afterSummary.today.failures == 1)
        } catch {
            await store.stop()
            throw error
        }
        await store.stop()
    }

    @Test("A corrupt database is rebuilt from scratch")
    func corruptDatabaseRebuilds() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not a database".utf8).write(to: fileURL)

        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        #expect(await store.summary(now: now).today.requests == 0)

        await store.fold(GatewayUsageEvent(finishedAt: now, outcome: .succeeded, client: .claude))
        await store.stop()
        let restarted = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        let summary = await restarted.summary(now: now)
        #expect(summary.today.requests == 1)
        let clients = await restarted.clientSummaries(now: now)
        #expect(clients[.claude]?.today.requests == 1)
        #expect(clients[.codex]?.today.requests == 0)
    }

    @Test("A damaged row is dropped without touching the other days")
    func damagedRowStartsEmpty() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let yesterday = storeCalendar.date(byAdding: .day, value: -1, to: now) ?? now
        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        await store.fold(
            GatewayUsageEvent(finishedAt: now, outcome: .succeeded, client: .claude)
        )
        await store.fold(
            GatewayUsageEvent(
                finishedAt: yesterday,
                outcome: .succeeded,
                client: .codex,
                usage: GatewayUsageTotals(inputTokens: 100, outputTokens: 20)
            )
        )
        await store.stop()
        let original = await store.summary(now: now)

        try await DatabaseQueue(path: fileURL.path).write { database in
            try database.execute(
                sql: "UPDATE usageDay SET targets = 'not json' WHERE day = ?",
                arguments: [GatewayUsageHistory.dayKey(for: now, calendar: storeCalendar)]
            )
        }

        let damaged = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        let damagedSummary = await damaged.summary(now: now)
        #expect(damagedSummary.today == .empty)
        // Every field and plotted token survives on the undamaged days.
        #expect(damagedSummary.dayDetails.dropLast() == original.dayDetails.dropLast())
        #expect(damagedSummary.points == original.points)

        // New requests still fold and flush over the damage.
        await damaged.fold(GatewayUsageEvent(finishedAt: now, outcome: .failed))
        await damaged.stop()
        let recovered = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        let summary = await recovered.summary(now: now)
        #expect(summary.today.requests == 1)
        #expect(summary.today.failures == 1)
        #expect(summary.dayDetails.dropLast() == original.dayDetails.dropLast())
        #expect(summary.points.dropLast() == original.points.dropLast())
    }

    @Test("Rows missing a migrated column are dropped without failing the read")
    func missingColumnQuarantined() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let yesterday = storeCalendar.date(byAdding: .day, value: -1, to: now) ?? now
        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        await store.fold(
            GatewayUsageEvent(finishedAt: now, outcome: .succeeded, client: .claude)
        )
        await store.fold(
            GatewayUsageEvent(finishedAt: yesterday, outcome: .succeeded, client: .codex)
        )
        await store.stop()

        // A database written by an older build lacks the newest column: the
        // migration registry still marks v1 applied, so opening succeeds and
        // the read must quarantine the short rows instead of failing.
        try await DatabaseQueue(path: fileURL.path).write { database in
            try database.execute(sql: "ALTER TABLE usageDay DROP COLUMN reportedUsageRequests")
        }

        let damaged = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        // Every stored row lacks the column, so every row is quarantined and
        // the store starts empty; the undamaged-row case is covered by the
        // damaged-JSON test above.
        #expect(
            await damaged.summary(now: now)
                == GatewayUsageSummary(history: GatewayUsageHistory(), now: now, calendar: storeCalendar)
        )
        await damaged.stop()
    }

    @Test("A read failure beyond a damaged row starts the store empty")
    func unreadableSchemaStartsEmpty() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        await store.fold(
            GatewayUsageEvent(finishedAt: now, outcome: .succeeded, client: .claude)
        )
        await store.stop()

        // Replace the table with a view whose source is missing: opening and
        // migrating still succeed, but the read itself throws.
        try await DatabaseQueue(path: fileURL.path).write { database in
            try database.execute(sql: "DROP TABLE usageDay")
            try database.execute(sql: "CREATE VIEW usageDay AS SELECT * FROM missingUsageDay")
        }

        let broken = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        #expect(
            await broken.summary(now: now)
                == GatewayUsageSummary(history: GatewayUsageHistory(), now: now, calendar: storeCalendar)
        )
        await broken.stop()
    }

    @Test("An unopenable database keeps counting in memory")
    func unopenableDatabaseKeepsMemory() async throws {
        let fileURL = temporaryFileURL()
        let directory = fileURL.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: directory.path
            )
            try? FileManager.default.removeItem(at: directory)
        }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o555)],
            ofItemAtPath: directory.path
        )

        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        #expect(await store.summary(now: now).today.requests == 0)

        await store.fold(GatewayUsageEvent(finishedAt: now, outcome: .succeeded, client: .claude))
        let summary = await store.summary(now: now)
        #expect(summary.today.requests == 1)
        await store.stop()
    }

    @Test("The standard location sits beside the application support directory")
    func standardConfiguration() {
        let support = URL(fileURLWithPath: "/tmp/support", isDirectory: true)
        let home = URL(fileURLWithPath: "/tmp/home", isDirectory: true)

        let configured = GatewayUsageHistoryStore.Configuration.standard(
            applicationSupportDirectory: support,
            homeDirectory: home
        )
        let fallback = GatewayUsageHistoryStore.Configuration.standard(
            applicationSupportDirectory: nil,
            homeDirectory: home
        )

        #expect(configured.fileURL.lastPathComponent == "usage-history.sqlite")
        #expect(configured.flushInterval == .seconds(2))
        #expect(configured.fileURL.path.hasPrefix("/tmp/support/"))
        #expect(fallback.fileURL.path.hasPrefix("/tmp/home/"))
        #expect(
            GatewayUsageHistoryStore.Configuration.standard.fileURL.lastPathComponent
                == "usage-history.sqlite"
        )
    }
}
