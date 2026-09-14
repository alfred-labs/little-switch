import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring export presentation contracts")
struct MonitoringExportStatusTests {
    @Test("Product status messages never contain remote text or endpoint data")
    func safeMessages() {
        let warnings: [MonitoringExportWarning] = [.partialRejection, .receiverWarning, .deliveryUncertain]
        #expect(
            warnings.map(\.message) == [
                "The receiver accepted the batch with some rejected items.",
                "The receiver accepted the batch with a warning.",
                "The interrupted batch may already have reached the receiver.",
            ])
        let issues: [MonitoringExportConfigurationIssue] = [.invalidInterval, .invalidEndpoint, .missingCredential]
        #expect(
            issues.map(\.message) == [
                "Choose an export interval between 5 and 300 seconds.",
                "Enter a valid receiver URL.",
                "The receiver's saved token is missing or invalid.",
            ])
        let outcomes: [MonitoringExportTestOutcome] = [
            .disabled, .accepted, .partial(rejected: 2), .warning, .retrying(.network), .failed(.tls),
            .invalidConfiguration(.invalidInterval), .cancelled,
        ]
        #expect(
            outcomes.map(\.message) == [
                "Disabled", "Accepted", "Accepted with 2 rejected items.", "Accepted with a receiver warning.",
                "Retry scheduled. The receiver could not be reached.",
                "The receiver's secure connection could not be verified.",
                "Choose an export interval between 5 and 300 seconds.",
                "The test was interrupted; delivery is uncertain.",
            ])
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
