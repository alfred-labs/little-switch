import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring exporter retry isolation")
struct MonitoringExportRetryTests {
    @Test("A snapshot captured during an active metric send replaces it when that send fails")
    func replacementDuringSend() async throws {
        let clock = MonitoringManualExportClock()
        let transport = MonitoringRecordingTransport(responses: [exportResponse(503, retryAfter: "10")])
        await transport.hold()
        let store = MonitoringStore()
        await store.recordAdmission(.overloaded)
        let service = MonitoringExportService(store: store, transportFactory: { _ in transport }, clock: clock)
        await service.configure(exportConfiguration(metrics: true, logs: false))
        await clock.advance(by: .seconds(5))
        try await exportEventually { await transport.activeCount == 1 }
        await store.recordAdmission(.overloaded)
        await clock.advance(by: .seconds(5))
        try await exportEventually { await clock.isSleeping(until: .seconds(15)) }
        #expect(await service.status().metrics.queuedCount == 2)
        await transport.release()
        try await exportEventually { await service.status().metrics.state == .retrying }
        #expect(await service.status().metrics.queuedCount == 1)
        await clock.advance(by: .seconds(10))
        try await exportEventually { await service.status().metrics.lastAccepted != nil }
        #expect(await transport.calls.count == 2)
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("Long Retry-After prevents early log sends while metrics advance and old logs expire")
    func independentBackends() async throws {
        let clock = MonitoringManualExportClock()
        let metrics = MonitoringRecordingTransport()
        let logs = MonitoringRecordingTransport(responses: [exportResponse(429, retryAfter: "600")])
        let store = MonitoringStore()
        _ = await store.markTest()
        let service = MonitoringExportService(
            store: store, transportFactory: { $0 == .metrics ? metrics : logs }, clock: clock)
        await service.configure(exportConfiguration(metrics: true))
        await service.enqueue(.operation(.gatewayStarted))
        await clock.advance(by: .seconds(2))
        try await exportEventually { await service.status().logs.state == .retrying }
        #expect(await service.status().logs.nextRetry == Date(timeIntervalSince1970: 1_602))
        await clock.advance(by: .seconds(3))
        try await exportEventually { await metrics.calls.count == 1 }
        await clock.advance(by: .seconds(300))
        try await exportEventually { await service.status().logs.drops[.expired] == 1 }
        try await exportEventually { await metrics.calls.count == 2 }
        #expect(await logs.calls.count == 1)
        #expect(await service.status().logs.queuedCount == 0)
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("A metric retry uses the newest cumulative snapshot without an early attempt")
    func newestCumulativeSnapshot() async throws {
        let clock = MonitoringManualExportClock()
        let transport = MonitoringRecordingTransport(responses: [exportResponse(503, retryAfter: "10")])
        let store = MonitoringStore()
        await store.recordAdmission(.overloaded)
        let service = MonitoringExportService(store: store, transportFactory: { _ in transport }, clock: clock)
        await service.configure(exportConfiguration(metrics: true, logs: false))
        await clock.advance(by: .seconds(5))
        try await exportEventually { await service.status().metrics.state == .retrying }
        await store.recordAdmission(.overloaded)
        await clock.advance(by: .seconds(5))
        try await exportEventually { await clock.isSleeping(until: .seconds(15)) }
        #expect(await service.status().metrics.queuedCount == 1)
        #expect(await transport.calls.count == 1)
        await clock.advance(by: .seconds(5))
        try await exportEventually { await service.status().metrics.lastAccepted != nil }
        let calls = await transport.calls
        #expect(calls.count == 2)
        let latest = try #require(calls.last)
        let text = try #require(String(bytes: latest.body, encoding: .utf8))
        #expect(text.contains(#""asInt":"2""#))
        #expect(text.contains(#""timeUnixNano":"1015000000000""#))
        #expect(text.contains(#""startTimeUnixNano""#))
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("Retry keeps the same log bytes and a permanent response retires the batch")
    func stableRetryThenPermanentFailure() async throws {
        let clock = MonitoringManualExportClock()
        let transport = MonitoringRecordingTransport(responses: [exportResponse(502), exportResponse(401)])
        let service = MonitoringExportService(
            store: .init(), transportFactory: { _ in transport }, clock: clock, jitter: { 1 }, logLimits: .init())
        await service.configure(exportConfiguration())
        await service.enqueue(.operation(.test))
        await clock.advance(by: .seconds(2))
        try await exportEventually { await service.status().logs.state == .retrying }
        await clock.advance(by: .seconds(1))
        try await exportEventually { await service.status().logs.state == .failed }
        let calls = await transport.calls
        #expect(calls.count == 2)
        #expect(calls.first?.body == calls.last?.body)
        #expect(await service.status().logs.drops == [.rejected: 1])
        #expect(await service.status().logs.queuedCount == 0)
        #expect(await service.status().logs.failure == .httpStatus(401))
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("A level edit filters pending events without loss accounting or cancelling the active send")
    func intentionalLevelFilter() async throws {
        let transport = MonitoringRecordingTransport()
        await transport.hold()
        let service = MonitoringExportService(
            store: .init(), transportFactory: { _ in transport }, logLimits: .init(maximumBatchEntries: 1))
        var configuration = exportConfiguration()
        await service.configure(configuration)
        await service.enqueue(.operation(.gatewayStarted))
        try await exportEventually { await transport.activeCount == 1 }
        await service.enqueue(.operation(.gatewayStopped))
        configuration.minimumLogLevel = .error
        await service.configure(configuration)
        #expect(await transport.activeCount == 1)
        #expect(await transport.shutdownCount == 0)
        #expect(await service.status().logs.queuedCount == 1)
        #expect(await service.status().logs.droppedCount == 0)
        await transport.release()
        try await exportEventually { await service.status().logs.lastAccepted != nil }
        #expect(await transport.calls.count == 1)
        let test = await service.testExport()
        #expect(test.logs == .accepted)
        #expect(await transport.calls.count == 2)
        await service.shutdown(flushTimeout: .zero)
    }
}
