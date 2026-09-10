import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring exporter lifecycle")
struct MonitoringExportLifecycleTests {
    @Test("The production transport is constructed only after a valid signal is enabled")
    func productionTransportLifecycle() async {
        let service = MonitoringExportService(store: .init())
        await service.configure(exportConfiguration(metrics: true, logs: false))
        #expect(await service.status().metrics.state == .idle)
        await service.shutdown(flushTimeout: .zero)
        #expect(await service.status().metrics.state == .disabled)
    }

    @Test("An interval edit is validated even when the destination did not change")
    func invalidIntervalReconfiguration() async {
        let transport = MonitoringRecordingTransport()
        let service = MonitoringExportService(
            store: .init(), transportFactory: { _ in transport }, clock: MonitoringContinuousExportClock())
        var configuration = exportConfiguration(metrics: true, logs: false)
        await service.configure(configuration)
        configuration.metricIntervalSeconds = 0
        await service.configure(configuration)
        #expect(await service.status().metrics.configurationIssue == .invalidInterval)
        #expect(await transport.shutdownCount == 1)
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("A new destination joins the old send and discards its active and waiting entries")
    func reconfigurationJoinsOldGeneration() async throws {
        let clock = MonitoringManualExportClock()
        let transport = MonitoringRecordingTransport()
        await transport.hold()
        let service = MonitoringExportService(
            store: .init(),
            transportFactory: { _ in transport },
            clock: clock,
            logLimits: .init(maximumBatchEntries: 1))
        var configuration = exportConfiguration()
        await service.configure(configuration)
        await service.enqueue(.operation(.gatewayStarted))
        try await exportEventually { await transport.activeCount == 1 }
        await service.enqueue(.operation(.gatewayStopped))
        configuration.logs.endpoint = "http://127.0.0.1:4319/new/logs"
        await service.configure(configuration)
        let status = await service.status().logs
        #expect(status.state == .idle)
        #expect(status.lastAccepted == nil)
        #expect(status.warning == .deliveryUncertain)
        #expect(status.drops == [.reconfigured: 2])
        #expect(status.queuedCount == 0)
        #expect(await transport.activeCount == 0)
        #expect(await transport.shutdownCount == 1)
        await service.enqueue(.operation(.test))
        try await exportEventually { await service.status().logs.lastAccepted != nil }
        #expect(await transport.calls.last?.endpoint.absoluteString == configuration.logs.endpoint)
        #expect(await transport.maximumActiveCount == 1)
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("Disabling acknowledges no more sends and reactivation does not replay local history")
    func disableAndReactivate() async throws {
        let clock = MonitoringManualExportClock()
        let transport = MonitoringRecordingTransport()
        let store = MonitoringStore()
        let service = MonitoringExportService(store: store, transportFactory: { _ in transport }, clock: clock)
        var configuration = exportConfiguration()
        await service.configure(configuration)
        _ = await store.recordOperation(.gatewayStarted)
        let first = await service.testExport()
        #expect(first.logs == .accepted)
        await service.enqueue(.operation(.gatewayStopped))
        configuration.logs.enabled = false
        await service.configure(configuration)
        #expect(await service.status().logs.lastAccepted == nil)
        #expect(await service.status().logs.drops == [.reconfigured: 1])
        await service.enqueue(.operation(.test))
        await clock.advance(by: .seconds(400))
        #expect(await transport.calls.count == 1)
        configuration.logs.enabled = true
        await service.configure(configuration)
        #expect(await service.status().logs.queuedCount == 0)
        await service.enqueue(.operation(.test))
        await clock.advance(by: .seconds(2))
        try await exportEventually { await transport.calls.count == 2 }
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("The final deadline cancels a slow receiver and joins both transports")
    func boundedShutdown() async throws {
        let clock = MonitoringManualExportClock()
        let metrics = MonitoringRecordingTransport(responses: [exportResponse(503, retryAfter: "600")])
        let logs = MonitoringRecordingTransport()
        await logs.hold()
        let store = MonitoringStore()
        _ = await store.markTest()
        let service = MonitoringExportService(
            store: store,
            transportFactory: { $0 == .metrics ? metrics : logs },
            clock: clock,
            logLimits: .init(maximumBatchEntries: 1))
        await service.configure(exportConfiguration(metrics: true))
        await service.enqueue(.operation(.test))
        await clock.advance(by: .seconds(5))
        try await exportEventually {
            let active = await logs.activeCount
            let status = await service.status()
            return active == 1 && status.metrics.state == .retrying
        }
        let started = ContinuousClock.now
        await service.shutdown(flushTimeout: .milliseconds(30))
        #expect(started.duration(to: .now) < .seconds(1))
        #expect(await metrics.shutdownCount == 1)
        #expect(await logs.shutdownCount == 1)
        #expect(await logs.activeCount == 0)
        #expect(await service.status().logs.state == .disabled)
        #expect(await service.status().logs.drops == [.transportFailure: 1])
    }

    @Test("Disabled signals never construct a transport")
    func lazyTransports() async {
        let transport = MonitoringRecordingTransport()
        let service = MonitoringExportService(
            store: .init(),
            transportFactory: { _ in
                Issue.record("Disabled monitoring constructed a transport.")
                return transport
            },
            clock: MonitoringContinuousExportClock())
        await service.configure(.init())
        await service.enqueue(.operation(.test))
        #expect(await service.testExport() == .init())
        #expect(await service.status() == .init())
        await service.shutdown(flushTimeout: .zero)
    }
}
