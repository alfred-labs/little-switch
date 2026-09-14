import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring bounded delivery queue")
struct MonitoringLogExportQueueTests {
    @Test("Pressure includes the active batch and evicts the oldest waiting event")
    func pressurePreservesActiveBatch() throws {
        var queue = MonitoringLogExportQueue(
            resource: .init(), limits: .init(maximumEntries: 3, maximumBatchEntries: 1))
        let entries = (0..<4).map { MonitoringLogEntry.operation(.test, at: Date(timeIntervalSince1970: Double($0))) }
        #expect({ queue.append(entries[0], at: .zero) }().isEmpty)
        let started = queue.beginBatch()
        let first = try #require(started)
        #expect(first.entries == [entries[0]])
        #expect(queue.contains(entries[0].eventID))
        #expect(!queue.contains(entries[1].eventID))
        #expect({ queue.append(entries[1], at: .seconds(1)) }().isEmpty)
        #expect({ queue.append(entries[2], at: .seconds(2)) }().isEmpty)
        #expect({ queue.append(entries[3], at: .seconds(3)) }() == [.queueFull: 1])
        #expect(queue.retainedCount == 3)
        #expect(queue.batch?.entries == [entries[0]])
        queue.finishBatch()
        let next = queue.beginBatch()
        #expect(next?.entries == [entries[2]])
    }

    @Test("Batch and retained byte ceilings include the OTLP envelope")
    func exactByteCeilings() throws {
        let resource = MonitoringResource()
        let entry = MonitoringLogEntry.operation(.test)
        let size = try OTLPLogsEncoder.encode(resource: resource, entries: [entry]).count
        var rejected = MonitoringLogExportQueue(resource: resource, limits: .init(maximumBatchBytes: size - 1))
        #expect({ rejected.append(entry, at: .zero) }() == [.oversize: 1])
        var bounded = MonitoringLogExportQueue(
            resource: resource, limits: .init(maximumBytes: size, maximumBatchBytes: size))
        #expect({ bounded.append(entry, at: .zero) }().isEmpty)
        #expect(bounded.retainedBytes == size)
        #expect({ bounded.append(entry, at: .zero) }() == [.queueFull: 1])
        let started = bounded.beginBatch()
        let batch = try #require(started)
        #expect(batch.body.count == size)
        #expect({ bounded.append(entry, at: .zero) }() == [.queueFull: 1])
        #expect(bounded.retainedCount == 1)
    }

    @Test("Expiry uses queue residence on a monotonic clock, including a held retry")
    func monotonicExpiry() throws {
        var queue = MonitoringLogExportQueue(resource: .init(), limits: .init(maximumBatchEntries: 1))
        #expect({ queue.append(.operation(.test, at: .distantFuture), at: .zero) }().isEmpty)
        let started = queue.beginBatch()
        _ = try #require(started)
        #expect({ queue.append(.operation(.test, at: .distantPast), at: .seconds(100)) }().isEmpty)
        #expect({ queue.expire(at: .seconds(299)) }() == 0)
        #expect({ queue.expire(at: .seconds(300)) }() == 1)
        #expect(queue.retainedCount == 1)
        #expect(queue.batch == nil)
        #expect({ queue.expire(at: .seconds(400)) }() == 1)
        #expect(queue.retainedBytes == 0)
    }

    @Test("Level filtering is intentional and never changes an active send")
    func levelFiltering() throws {
        var queue = MonitoringLogExportQueue(resource: .init(), limits: .init(maximumBatchEntries: 1))
        let entry = MonitoringLogEntry.operation(.test)
        #expect({ queue.append(entry, at: .zero) }().isEmpty)
        let started = queue.beginBatch()
        _ = try #require(started)
        #expect({ queue.append(entry, at: .zero) }().isEmpty)
        queue.filter(minimumLevel: .error, includingBatch: false)
        #expect(queue.retainedCount == 1)
        queue.filter(minimumLevel: .error)
        #expect(queue.retainedCount == 0)
        #expect(queue.discardAll() == 0)
    }

    @Test("A size-limited batch splits whole records and a partly expired retry preserves the newer record")
    func splitAndPartialExpiry() throws {
        let resource = MonitoringResource()
        let first = MonitoringLogEntry.operation(.gatewayStarted)
        let second = MonitoringLogEntry.operation(.gatewayStopped)
        let singleBytes = try OTLPLogsEncoder.encode(resource: resource, entries: [first]).count
        var split = MonitoringLogExportQueue(
            resource: resource, limits: .init(maximumBatchBytes: singleBytes + 20))
        #expect({ split.append(first, at: .zero) }().isEmpty)
        #expect({ split.append(second, at: .zero) }().isEmpty)
        let selected = split.beginBatch()
        #expect(selected?.entries == [first])
        #expect(split.retainedCount == 2)
        split.finishBatch()
        _ = split.beginBatch()
        split.finishBatch()
        let empty = split.beginBatch()
        #expect(empty == nil)
        var expiry = MonitoringLogExportQueue(resource: resource)
        #expect({ expiry.append(first, at: .zero) }().isEmpty)
        #expect({ expiry.append(second, at: .seconds(100)) }().isEmpty)
        _ = expiry.beginBatch()
        #expect({ expiry.expire(at: .seconds(300)) }() == 1)
        #expect(expiry.batch?.entries == [second])
        #expect(expiry.batch?.body == (try OTLPLogsEncoder.encode(resource: resource, entries: [second])))
    }
}
