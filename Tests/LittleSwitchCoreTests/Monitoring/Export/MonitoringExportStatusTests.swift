import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring export presentation contracts")
struct MonitoringExportStatusTests {
    @Test("Dropped event counts saturate instead of overflowing")
    func droppedCountsSaturate() {
        let status = MonitoringSignalExportStatus(drops: [.expired: .max, .queueFull: 1])
        #expect(status.droppedCount == UInt64(Int64.max))
    }

    @Test("The production monotonic clock completes an already elapsed deadline")
    func productionClock() async throws {
        let clock = MonitoringContinuousExportClock()
        try await clock.sleep(until: .zero)
        #expect(await clock.now().monotonic >= .zero)
    }

    @Test("An interval edit retains totals and refreshes the injected provider pool")
    func intervalAndPool() async throws {
        let clock = MonitoringManualExportClock()
        let transport = MonitoringRecordingTransport()
        let store = MonitoringStore()
        await store.recordAdmission(.overloaded)
        let service = MonitoringExportService(store: store, transportFactory: { _ in transport }, clock: clock)
        var configuration = exportConfiguration(metrics: true, logs: false)
        await service.configure(configuration)
        let state = GatewayState(snapshot: .init(generation: 0, providers: [], mappings: [:]))
        await service.updateProviderPool(state)
        configuration.metricIntervalSeconds = 10
        await service.configure(configuration)
        await clock.advance(by: .seconds(5))
        #expect(await transport.calls.isEmpty)
        await clock.advance(by: .seconds(5))
        try await exportEventually { await transport.calls.count == 1 }
        #expect(await service.status().metrics.droppedCount == 0)
        #expect(await transport.shutdownCount == 0)
        await service.updateProviderPool(nil)
        await service.shutdown(flushTimeout: .zero)
    }
}
