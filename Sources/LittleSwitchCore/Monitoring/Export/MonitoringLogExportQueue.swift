import Foundation
import LittleSwitchCommon

package struct MonitoringLogExportLimits: Sendable {
    package var maximumEntries = 5_000
    package var maximumBytes = 5 * 1_024 * 1_024
    package var maximumBatchEntries = 256
    package var maximumBatchBytes = 512 * 1_024
    package var retention: Duration = .seconds(300)
}

package struct MonitoringQueuedLogBatch: Sendable {
    package let entries: [MonitoringLogEntry]
    package let body: Data
}

package struct MonitoringLogExportQueue: Sendable {
    private struct StoredEntry: Sendable {
        let entry: MonitoringLogEntry
        let enqueuedAt: Duration
        let bytes: Int
    }

    private let resource: MonitoringResource
    private let limits: MonitoringLogExportLimits
    private var waiting: [StoredEntry] = []
    private var held: [StoredEntry] = []
    package private(set) var retainedBytes = 0
    package private(set) var batch: MonitoringQueuedLogBatch?
    package var retainedCount: Int { waiting.count + held.count }
    package var waitingCount: Int { waiting.count }
    package var oldestEnqueuedAt: Duration? { held.first?.enqueuedAt ?? waiting.first?.enqueuedAt }
    package var oldestWaitingAt: Duration? { waiting.first?.enqueuedAt }

    package init(resource: MonitoringResource, limits: MonitoringLogExportLimits = .init()) {
        self.resource = resource
        self.limits = limits
    }

    package mutating func append(
        _ entry: MonitoringLogEntry, at now: Duration, preservingBatch: Bool = true
    ) -> [MonitoringDropReason: UInt64] {
        guard let encoded = try? OTLPLogsEncoder.encode(resource: resource, entries: [entry]),
            encoded.count <= limits.maximumBatchBytes, encoded.count <= limits.maximumBytes
        else { return [.oversize: 1] }
        var dropped: UInt64 = 0
        let heldCount = held.count
        // The full single-entry envelope is charged for every entry. This conservative
        // accounting includes the batch envelope while the send remains unacknowledged.
        while !hasCapacity(for: encoded.count) {
            if !preservingBatch, !held.isEmpty {
                retainedBytes -= held.removeFirst().bytes
            } else if !waiting.isEmpty {
                retainedBytes -= waiting.removeFirst().bytes
            } else {
                break
            }
            dropped += 1
        }
        if held.count != heldCount { rebuildBatch() }
        guard hasCapacity(for: encoded.count) else {
            return [.queueFull: dropped + 1]
        }
        waiting.append(StoredEntry(entry: entry, enqueuedAt: now, bytes: encoded.count))
        retainedBytes += encoded.count
        return dropped == 0 ? [:] : [.queueFull: dropped]
    }

    package mutating func beginBatch() -> MonitoringQueuedLogBatch? {
        if let batch { return batch }
        var count = min(waiting.count, max(1, limits.maximumBatchEntries))
        while count > 0 {
            let selected = Array(waiting.prefix(count))
            let encoded = try? OTLPLogsEncoder.encode(resource: resource, entries: selected.map(\.entry))
            if let body = encoded, body.count <= limits.maximumBatchBytes {
                held = selected
                waiting.removeFirst(count)
                batch = .init(entries: selected.map(\.entry), body: body)
                return batch
            }
            count /= 2
        }
        return nil
    }

    package mutating func finishBatch() {
        retainedBytes -= held.reduce(0) { $0 + $1.bytes }
        held.removeAll(keepingCapacity: true)
        batch = nil
    }

    package mutating func expire(at now: Duration, includingBatch: Bool = true) -> UInt64 {
        let original = retainedCount
        let retention = limits.retention
        retain(includingBatch: includingBatch) { now - $0.enqueuedAt < retention }
        return UInt64(original - retainedCount)
    }

    package mutating func filter(minimumLevel: MonitoringLevel, includingBatch: Bool = true) {
        retain(includingBatch: includingBatch) { $0.entry.level >= minimumLevel }
    }

    package mutating func discardAll() -> UInt64 {
        let count = UInt64(retainedCount)
        waiting.removeAll(keepingCapacity: false)
        finishBatch()
        retainedBytes = 0
        return count
    }

    package func contains(_ eventID: UUID) -> Bool {
        held.contains { $0.entry.eventID == eventID } || waiting.contains { $0.entry.eventID == eventID }
    }

    private func hasCapacity(for byteCount: Int) -> Bool {
        retainedCount < limits.maximumEntries && retainedBytes + byteCount <= limits.maximumBytes
    }

    private mutating func retain(includingBatch: Bool, where predicate: (StoredEntry) -> Bool) {
        waiting.removeAll { !predicate($0) }
        if includingBatch {
            let oldCount = held.count
            held.removeAll { !predicate($0) }
            if held.count != oldCount { rebuildBatch() }
        }
        retainedBytes = waiting.reduce(0) { $0 + $1.bytes } + held.reduce(0) { $0 + $1.bytes }
    }

    private mutating func rebuildBatch() {
        batch =
            held.isEmpty
            ? nil
            : try? MonitoringQueuedLogBatch(
                entries: held.map(\.entry),
                body: OTLPLogsEncoder.encode(resource: resource, entries: held.map(\.entry)))
    }
}
