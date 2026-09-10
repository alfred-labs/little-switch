import Foundation
import LittleSwitchCore

/// Sink for finished requests, kept nonisolated so the traffic log can hand off
/// a record without waiting on persistence.
protocol GatewayUsageRecording: Sendable {
    func record(_ event: GatewayUsageEvent)
}

/// Durable per-day gateway traffic behind the status menu's stats.
///
/// The traffic log rotates within minutes under load, so the thirty-day series
/// cannot come from it. Finished requests fold into in-memory day aggregates
/// and reach the SQLite database in coalesced flushes — at most one write per
/// flush interval, plus one whenever the store stops.
public actor GatewayUsageHistoryStore {
    public struct Configuration: Equatable, Sendable {
        /// The SQLite database holding the day aggregates.
        public var fileURL: URL
        /// How long a fold may stay in memory before reaching disk; nil flushes
        /// on every fold.
        public var flushInterval: Duration?

        public init(fileURL: URL, flushInterval: Duration? = nil) {
            self.fileURL = fileURL
            self.flushInterval = flushInterval
        }

        public static var standard: Configuration {
            standard(
                applicationSupportDirectory: FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
        }

        package static func standard(
            applicationSupportDirectory: URL?,
            homeDirectory: URL
        ) -> Configuration {
            let base = applicationSupportDirectory ?? homeDirectory
            let directory = base.appendingPathComponent(
                ProductIdentity.applicationSupportDirectoryName,
                isDirectory: true
            )
            return Configuration(
                fileURL: directory.appendingPathComponent("usage-history.sqlite", isDirectory: false),
                flushInterval: .seconds(2)
            )
        }
    }

    nonisolated private let inbox: GatewayUsageInbox
    nonisolated private let configuration: Configuration
    nonisolated private let calendar: Calendar
    private var database: GatewayUsageHistoryDatabase?
    private var history = GatewayUsageHistory()
    private var loaded = false
    private var pendingDayKeys: Set<String> = []
    private var consumerTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?

    public init(
        configuration: Configuration = .standard,
        calendar: Calendar = .current
    ) {
        self.configuration = configuration
        self.calendar = calendar
        inbox = GatewayUsageInbox()
    }

    public func start() {
        guard consumerTask == nil else { return }
        load()
        let stream = inbox.stream
        consumerTask = Task { [weak self] in
            for await event in stream {
                await self?.fold(event)
            }
        }
    }

    public func stop() async {
        inbox.finish()
        await consumerTask?.value
        consumerTask = nil
        flushNow()
    }

    public func summary(now: Date = Date()) -> GatewayUsageSummary {
        load()
        return GatewayUsageSummary(history: history, now: now, calendar: calendar)
    }

    /// Per-client consumption behind the menu's provider tabs.
    func clientSummaries(
        now: Date = Date()
    ) -> [GatewayClient: GatewayUsageSummary] {
        load()
        return GatewayClient.allCases.reduce(into: [:]) { result, client in
            result[client] = GatewayUsageSummary(
                history: history,
                client: client,
                now: now,
                calendar: calendar
            )
        }
    }

    /// The most recent fold, without waiting on persistence.
    public func fold(_ event: GatewayUsageEvent) {
        load()
        pendingDayKeys.insert(GatewayUsageHistory.dayKey(for: event.finishedAt, calendar: calendar))
        history.fold(event, calendar: calendar)
        scheduleFlush()
    }

    /// Writes every day touched since the last flush to the database.
    public func flushNow() {
        flushTask?.cancel()
        flushTask = nil
        guard let database, !pendingDayKeys.isEmpty else { return }
        let days = pendingDayKeys.compactMap { key in history.day(key) }
        do {
            try database.writeDays(days)
            // Only a successful write retires the pending keys; a failed
            // flush keeps its deltas pending so they ride the next one.
            pendingDayKeys.removeAll()
            pruneExpiredDays(in: database)
        } catch {
            // A failed flush is not final: the deltas stay pending and the
            // store retries on its own, because nothing else may ever fold
            // again on an idle gateway. The next fold coalesces into the
            // same pending retry instead of stacking timers.
            retryFailedFlush()
        }
    }

    /// Arms one delayed retry for a failed flush. Runs even when flushing is
    /// synchronous (`flushInterval == nil`) — an immediate retry there would
    /// just recurse on a persistent failure.
    private func retryFailedFlush() {
        let interval = configuration.flushInterval ?? .seconds(2)
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            await self?.flushNow()
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        guard let interval = configuration.flushInterval else {
            flushNow()
            return
        }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            await self?.flushNow()
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard
            let database = GatewayUsageHistoryDatabase.opening(fileURL: configuration.fileURL)
        else {
            return
        }
        self.database = database
        do {
            let days = try database.readDays()
            history = GatewayUsageHistory(days: days)
            pruneExpiredDays(in: database)
        } catch {
            // A read failure beyond a quarantined row must not take the
            // gateway down: the in-memory counters start fresh and rewrite
            // the days they touch.
        }
    }

    /// Keeps the database as narrow as the window the menu actually reads:
    /// the trimming at fold time only bounds memory, so days that fall out
    /// of the retention calendar are deleted here instead of accumulating
    /// one row per local day forever. The window ends at the newest stored
    /// day, so a dormant install never deletes its own last rows.
    private func pruneExpiredDays(in database: GatewayUsageHistoryDatabase) {
        guard
            let newest = history.days.last,
            let anchor = try? Date(
                newest.day,
                strategy: .iso8601.year().month().day()
            )
        else { return }
        let cutoff = GatewayUsageHistory.dayKeys(
            endingAt: anchor,
            count: GatewayUsageHistory.retainedDays,
            calendar: calendar
        ).first
        guard let cutoff else { return }
        try? database.pruneDays(olderThan: cutoff)
    }
}

extension GatewayUsageHistoryStore: GatewayUsageRecording {
    nonisolated public func record(_ event: GatewayUsageEvent) {
        inbox.yield(event)
    }
}

private final class GatewayUsageInbox: Sendable {
    let stream: AsyncStream<GatewayUsageEvent>
    private let continuation: AsyncStream<GatewayUsageEvent>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: GatewayUsageEvent.self)
    }

    func yield(_ event: GatewayUsageEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }
}
