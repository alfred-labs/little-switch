import Foundation

package struct MonitoringLogLimits: Sendable {
    package var maximumEntries = 1_000
    package var maximumBytes = 2 * 1_024 * 1_024
    package var maximumEntryBytes = 4_096
    package var maximumResponseBytes = 1_024 * 1_024
}

/// Local consultation retention is independent of the exporter delivery queue.
package struct MonitoringLogBuffer: Sendable {
    private struct StoredEntry: Sendable {
        let position: UInt64
        let entry: MonitoringLogEntry
        let byteCount: Int
    }

    private let instanceID: UUID
    private let limits: MonitoringLogLimits
    private var entries: [StoredEntry] = []
    private var latestPosition: UInt64 = 0
    private var evictedThrough: UInt64 = 0
    private var latestEvictedTimestamp: Date?
    package private(set) var retainedByteCount = 0

    package init(instanceID: UUID, limits: MonitoringLogLimits = .init()) {
        self.instanceID = instanceID
        self.limits = limits
    }

    package mutating func append(_ entry: MonitoringLogEntry) -> Bool {
        guard let data = try? MonitoringLogPage.encoder().encode(entry),
            data.count <= limits.maximumEntryBytes, data.count <= limits.maximumBytes,
            limits.maximumEntries > 0, latestPosition < UInt64.max
        else { return false }
        latestPosition += 1
        entries.append(StoredEntry(position: latestPosition, entry: entry, byteCount: data.count))
        retainedByteCount += data.count
        while entries.count > limits.maximumEntries || retainedByteCount > limits.maximumBytes {
            let removed = entries.removeFirst()
            retainedByteCount -= removed.byteCount
            evictedThrough = removed.position
            latestEvictedTimestamp = max(latestEvictedTimestamp ?? removed.entry.timestamp, removed.entry.timestamp)
        }
        return true
    }

    package func page(query: MonitoringLogQuery) throws -> MonitoringLogPage {
        var position = try startingPosition(query: query)
        let retentionLost =
            query.cursor == nil
            && query.filters.since.map { date in latestEvictedTimestamp.map { date <= $0 } ?? false } == true
        let reservedCursor = try cursor(position: UInt64.max, filters: query.filters)
        let empty = MonitoringLogPage(entries: [], nextCursor: reservedCursor, retentionLost: retentionLost)
        var byteCount = try empty.encoded().count
        var selected: [MonitoringLogEntry] = []
        for stored in entries where stored.position > position {
            if query.filters.matches(stored.entry) {
                let additionalBytes = stored.byteCount + (selected.isEmpty ? 0 : 1)
                guard byteCount + additionalBytes <= limits.maximumResponseBytes else { break }
                selected.append(stored.entry)
                byteCount += additionalBytes
            }
            position = stored.position
            if selected.count == query.limit { break }
        }
        return MonitoringLogPage(
            entries: selected,
            nextCursor: try cursor(position: position, filters: query.filters),
            retentionLost: retentionLost)
    }

    private func startingPosition(query: MonitoringLogQuery) throws -> UInt64 {
        if let cursor = query.cursor {
            guard cursor.instanceID == instanceID, cursor.position >= evictedThrough else {
                throw MonitoringLogQueryError.cursorExpired
            }
            guard cursor.position <= latestPosition else { throw MonitoringLogQueryError.invalidQuery }
            return cursor.position
        }
        if query.filters.since != nil { return evictedThrough }
        let selected = entries.lazy.filter { query.filters.matches($0.entry) }.suffix(query.limit)
        return selected.first.map { $0.position - 1 } ?? latestPosition
    }

    private func cursor(position: UInt64, filters: MonitoringLogFilters) throws -> String {
        try MonitoringLogCursor(version: 1, instanceID: instanceID, position: position, filters: filters).encoded()
    }
}
