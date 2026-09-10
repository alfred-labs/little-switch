import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring retry retention review")
struct MonitoringExportRetentionReviewTests {
    @Test("An empty queue sleeps after its expired retry and flushes a later event in two seconds")
    func expiredRetryDoesNotSpin() async throws {
        let clock = MonitoringManualExportClock()
        let transport = MonitoringRecordingTransport(responses: [exportResponse(429, retryAfter: "600")])
        let service = MonitoringExportService(store: .init(), transportFactory: { _ in transport }, clock: clock)
        await service.configure(exportConfiguration())
        await service.enqueue(.operation(.gatewayStarted))
        await clock.advance(by: .seconds(2))
        try await exportEventually { await service.status().logs.state == .retrying }
        await clock.advance(by: .seconds(300))
        try await exportEventually { await service.status().logs.drops == [.expired: 1] }
        await clock.advance(by: .seconds(301))
        try await exportEventually { await clock.isSleeping(until: .seconds(903)) }
        #expect(await service.status().logs.queuedCount == 0)
        #expect(await transport.calls.count == 1)
        await service.enqueue(.operation(.gatewayStopped))
        try await exportEventually { await clock.isSleeping(until: .seconds(605)) }
        await clock.advance(by: .seconds(2))
        try await exportEventually { await service.status().logs.lastAccepted != nil }
        #expect(await transport.calls.count == 2)
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("Expiring the retry batch preserves a future Retry-After for newer logs")
    func expirationKeepsFutureBackoff() async throws {
        let clock = MonitoringManualExportClock()
        let transport = MonitoringRecordingTransport(responses: [exportResponse(429, retryAfter: "600")])
        let service = MonitoringExportService(
            store: .init(),
            transportFactory: { _ in transport },
            clock: clock,
            logLimits: .init(maximumBatchEntries: 1))
        await service.configure(exportConfiguration())
        await service.enqueue(.operation(.gatewayStarted))
        try await exportEventually { await service.status().logs.state == .retrying }
        await clock.advance(by: .seconds(400))
        try await exportEventually { await service.status().logs.drops == [.expired: 1] }
        await service.enqueue(.operation(.gatewayStopped))
        try await exportEventually { await clock.isSleeping(until: .seconds(600)) }
        await clock.advance(by: .seconds(199))
        #expect(await transport.calls.count == 1)
        await clock.advance(by: .seconds(1))
        try await exportEventually { await service.status().logs.lastAccepted != nil }
        #expect(await transport.calls.count == 2)
        #expect(await service.status().logs.drops == [.expired: 1])
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("Queue pressure discards the oldest retry when no request is active")
    func pressureDiscardsHeldRetry() async throws {
        let clock = MonitoringManualExportClock()
        let transport = MonitoringRecordingTransport(responses: [exportResponse(429, retryAfter: "10")])
        let store = MonitoringStore()
        let service = MonitoringExportService(
            store: store,
            transportFactory: { _ in transport },
            clock: clock,
            logLimits: .init(maximumEntries: 3, maximumBatchEntries: 1))
        let entries = (0..<4).map { _ in MonitoringLogEntry.operation(.test) }
        await service.configure(exportConfiguration())
        await service.enqueue(entries[0])
        try await exportEventually { await clock.isSleeping(until: .seconds(10)) }
        for entry in entries.dropFirst() { await service.enqueue(entry) }
        #expect(await service.status().logs.drops == [.queueFull: 1])
        #expect(await service.status().logs.queuedCount == 3)
        #expect(await transport.calls.count == 1)
        await clock.advance(by: .seconds(10))
        try await exportEventually { await service.status().logs.queuedCount == 0 }
        let expected = try entries.map { try OTLPLogsEncoder.encode(resource: store.resource, entries: [$0]) }
        #expect(await transport.calls.map(\.body) == expected)
        #expect(await transport.maximumActiveCount == 1)
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("Partially evicting a held retry preserves its newer event and re-encodes that batch")
    func pressureTrimsHeldRetry() async throws {
        let clock = MonitoringManualExportClock()
        let transport = MonitoringRecordingTransport(responses: [exportResponse(429, retryAfter: "10")])
        let store = MonitoringStore()
        let service = MonitoringExportService(
            store: store,
            transportFactory: { _ in transport },
            clock: clock,
            logLimits: .init(maximumEntries: 4, maximumBatchEntries: 2))
        let entries = (0..<5).map { _ in MonitoringLogEntry.operation(.test) }
        await service.configure(exportConfiguration())
        for entry in entries.prefix(2) { await service.enqueue(entry) }
        try await exportEventually { await clock.isSleeping(until: .seconds(10)) }
        for entry in entries.dropFirst(2) { await service.enqueue(entry) }
        #expect(await service.status().logs.drops == [.queueFull: 1])
        #expect(await service.status().logs.queuedCount == 4)
        await clock.advance(by: .seconds(10))
        try await exportEventually { await service.status().logs.queuedCount == 0 }
        let batches = [Array(entries.prefix(2)), [entries[1]], Array(entries[2...3]), [entries[4]]]
        let expected = try batches.map { try OTLPLogsEncoder.encode(resource: store.resource, entries: $0) }
        #expect(await transport.calls.map(\.body) == expected)
        #expect(await transport.maximumActiveCount == 1)
        await service.shutdown(flushTimeout: .zero)
    }
}
