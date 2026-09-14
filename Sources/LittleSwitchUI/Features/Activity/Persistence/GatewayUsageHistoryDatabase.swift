import Foundation
import GRDB
import LittleSwitchCommon
import LittleSwitchCore

/// SQLite persistence behind the gateway usage history: one row per local day.
///
/// The store folds events in memory and flushes whole day rows, so every write
/// is a self-contained upsert and a crash can only lose the requests recorded
/// since the last flush.
final class GatewayUsageHistoryDatabase: Sendable {
    private let queue: DatabaseQueue

    /// Opens the database, or rebuilds it from scratch when the file itself
    /// is damaged beyond repair: the counters are cheap, so a blank history
    /// beats a store that keeps failing on a corrupt file. Any other open
    /// failure — a lock held past the busy timeout, an unavailable disk —
    /// keeps the file untouched for the next launch instead of erasing a
    /// healthy history over a transient error.
    static func opening(fileURL: URL) -> GatewayUsageHistoryDatabase? {
        do {
            return try GatewayUsageHistoryDatabase(fileURL: fileURL)
        } catch {
            let databaseError = error as? DatabaseError
            let corrupted =
                databaseError?.resultCode.primaryResultCode == .SQLITE_CORRUPT
                || databaseError?.resultCode.primaryResultCode == .SQLITE_NOTADB
            guard corrupted else {
                return nil
            }
        }
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: fileURL.path + suffix)
        }
        return try? GatewayUsageHistoryDatabase(fileURL: fileURL)
    }

    private init(fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        var configuration = Configuration()
        configuration.journalMode = .wal
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA synchronous=NORMAL")
        }
        queue = try DatabaseQueue(path: fileURL.path, configuration: configuration)
        try Self.migrator.migrate(queue)
    }

    nonisolated private static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-create-usage-day") { database in
            try database.create(table: "usageDay") { table in
                table.primaryKey("day", .text)
                table.column("requests", .integer).notNull().defaults(to: 0)
                table.column("failures", .integer).notNull().defaults(to: 0)
                table.column("cancellations", .integer).notNull().defaults(to: 0)
                table.column("inputTokens", .integer).notNull().defaults(to: 0)
                table.column("outputTokens", .integer).notNull().defaults(to: 0)
                table.column("cacheReadTokens", .integer).notNull().defaults(to: 0)
                table.column("cacheWriteTokens", .integer).notNull().defaults(to: 0)
                table.column("estimatedTokens", .integer).notNull().defaults(to: 0)
                table.column("reportedUsageRequests", .integer).notNull().defaults(to: 0)
                table.column("latencyBuckets", .text).notNull().defaults(to: "[]")
                table.column("targets", .text).notNull().defaults(to: "{}")
                table.column("clients", .text).notNull().defaults(to: "{}")
            }
        }
        migrator.registerMigration("v2-add-client-usage") { database in
            try database.alter(table: "usageDay") { table in
                table.add(column: "clientUsage", .text).notNull().defaults(to: "{}")
            }
        }
        migrator.registerMigration("v2-tool-search-count") { database in
            try database.alter(table: "usageDay") { table in
                table.add(column: "toolSearchCount", .integer).notNull().defaults(to: 0)
            }
        }
        migrator.registerMigration("v3-web-search-count") { database in
            try database.alter(table: "usageDay") { table in
                table.add(column: "webSearchCount", .integer).notNull().defaults(to: 0)
            }
        }
        return migrator
    }()

    /// Every stored day, oldest first. A row that cannot be decoded is
    /// quarantined — deleted right after the read — instead of failing the
    /// whole read: one damaged day must not cost the other twenty-nine. The
    /// delete waits for its own write transaction because GRDB forbids write
    /// access inside a read one.
    func readDays() throws -> [GatewayUsageDay] {
        let decoder = JSONDecoder()
        let (days, damagedKeys) = try queue.read { database -> ([GatewayUsageDay], [DatabaseValue]) in
            var days: [GatewayUsageDay] = []
            var damagedKeys: [DatabaseValue] = []
            for row in try Row.fetchAll(database, sql: "SELECT * FROM usageDay ORDER BY day") {
                do {
                    days.append(try Self.day(from: row, decoder: decoder))
                } catch {
                    damagedKeys.append(row["day"])
                }
            }
            return (days, damagedKeys)
        }
        // A key that is itself damaged binds as a value no row carries, so the
        // delete is a harmless no-op for it.
        if !damagedKeys.isEmpty {
            try? queue.write { database in
                for key in damagedKeys {
                    try database.execute(
                        sql: "DELETE FROM usageDay WHERE day = ?",
                        arguments: [key]
                    )
                }
            }
        }
        return days
    }

    func writeDays(_ days: [GatewayUsageDay]) throws {
        let encoder = JSONEncoder()
        try queue.write { database in
            for day in days {
                try Self.upsert(day, database: database, encoder: encoder)
            }
        }
    }

    /// Deletes day rows that sort before `cutoff`. Keys are zero-padded
    /// `yyyy-MM-dd`, so lexicographic order is chronological order and a
    /// plain string bound is exact.
    func pruneDays(olderThan cutoff: String) throws {
        try queue.write { database in
            try database.execute(
                sql: "DELETE FROM usageDay WHERE day < ?",
                arguments: [cutoff]
            )
        }
    }

    private enum DamagedRow: Swift.Error {
        case damaged
    }

    private static func upsert(
        _ day: GatewayUsageDay,
        database: Database,
        encoder: JSONEncoder
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO usageDay (
                    day, requests, failures, cancellations,
                    inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens,
                    estimatedTokens, reportedUsageRequests, latencyBuckets, targets, clients,
                    clientUsage, toolSearchCount, webSearchCount
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(day) DO UPDATE SET
                    requests = excluded.requests,
                    failures = excluded.failures,
                    cancellations = excluded.cancellations,
                    inputTokens = excluded.inputTokens,
                    outputTokens = excluded.outputTokens,
                    cacheReadTokens = excluded.cacheReadTokens,
                    cacheWriteTokens = excluded.cacheWriteTokens,
                    estimatedTokens = excluded.estimatedTokens,
                    reportedUsageRequests = excluded.reportedUsageRequests,
                    latencyBuckets = excluded.latencyBuckets,
                    targets = excluded.targets,
                    clients = excluded.clients,
                    clientUsage = excluded.clientUsage,
                    toolSearchCount = excluded.toolSearchCount,
                    webSearchCount = excluded.webSearchCount
                """,
            arguments: [
                day.day,
                day.requests,
                day.failures,
                day.cancellations,
                day.usage.inputTokens,
                day.usage.outputTokens,
                day.usage.cacheReadTokens,
                day.usage.cacheWriteTokens,
                day.estimatedTokens,
                day.reportedUsageRequests,
                try Self.encodeJSON(day.latency.buckets, encoder: encoder),
                try Self.encodeJSON(day.targets, encoder: encoder),
                try Self.encodeJSON(day.clients, encoder: encoder),
                try Self.encodeJSON(day.clientUsage, encoder: encoder),
                day.toolSearchCount,
                day.webSearchCount,
            ]
        )
    }

    /// Optional column casts fail soft, so a damaged cell throws a
    /// quarantinable error instead of trapping the process.
    private static func day(from row: Row, decoder: JSONDecoder) throws -> GatewayUsageDay {
        guard
            let key = row["day"] as String?,
            let requests = row["requests"] as Int?,
            let failures = row["failures"] as Int?,
            let cancellations = row["cancellations"] as Int?,
            let inputTokens = row["inputTokens"] as Int?,
            let outputTokens = row["outputTokens"] as Int?,
            let cacheReadTokens = row["cacheReadTokens"] as Int?,
            let cacheWriteTokens = row["cacheWriteTokens"] as Int?,
            let estimatedTokens = row["estimatedTokens"] as Int?,
            let reportedUsageRequests = row["reportedUsageRequests"] as Int?,
            let latencyText = row["latencyBuckets"] as String?,
            let targetsText = row["targets"] as String?,
            let clientsText = row["clients"] as String?,
            let clientUsageText = row["clientUsage"] as String?,
            let toolSearchCount = row["toolSearchCount"] as Int?,
            let webSearchCount = row["webSearchCount"] as Int?
        else {
            throw DamagedRow.damaged
        }
        var day = GatewayUsageDay(day: key)
        day.requests = requests
        day.failures = failures
        day.cancellations = cancellations
        day.usage = GatewayUsageTotals(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens
        )
        day.estimatedTokens = estimatedTokens
        day.reportedUsageRequests = reportedUsageRequests
        day.toolSearchCount = toolSearchCount
        day.webSearchCount = webSearchCount
        day.latency = GatewayLatencyHistogram(
            buckets: try decode([Int].self, from: latencyText, decoder: decoder)
        )
        day.targets = try decode([String: Int].self, from: targetsText, decoder: decoder)
        day.clients = try decode([String: Int].self, from: clientsText, decoder: decoder)
        day.clientUsage = try decode(
            [String: GatewayClientUsage].self,
            from: clientUsageText,
            decoder: decoder
        )
        return day
    }

    private static func encodeJSON<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder
    ) throws -> String {
        // JSONEncoder only ever emits valid UTF-8.
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from text: String,
        decoder: JSONDecoder
    ) throws -> T {
        try decoder.decode(type, from: Data(text.utf8))
    }
}
