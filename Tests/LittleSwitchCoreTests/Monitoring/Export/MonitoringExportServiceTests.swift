import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring independent signal exporters")
struct MonitoringExportServiceTests {
    @Test("A two-second flush uses the normal queue and reports a complete acknowledgement")
    func logFlush() async throws {
        let clock = MonitoringManualExportClock()
        let transport = MonitoringRecordingTransport()
        let service = MonitoringExportService(store: .init(), transportFactory: { _ in transport }, clock: clock)
        await service.configure(exportConfiguration())
        await service.enqueue(.operation(.gatewayStarted))
        #expect(await transport.calls.isEmpty)
        await clock.advance(by: .seconds(2))
        try await exportEventually { await service.status().logs.lastAccepted != nil }
        #expect(await transport.calls.count == 1)
        #expect(await service.status().logs.queuedCount == 0)
        #expect(await service.status().logs.droppedCount == 0)
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("Invalid persisted values fail only the affected export and preserve local flags")
    func invalidConfiguration() async {
        let service = MonitoringExportService(store: .init())
        var configuration = exportConfiguration(metrics: true)
        configuration.exposeMetrics = false
        configuration.exposeLogs = true
        configuration.metricIntervalSeconds = 1
        configuration.logs.endpoint = "https://receiver.invalid/path?credential=private"
        await service.configure(configuration)
        let status = await service.status()
        #expect(status.metrics.state == .failed)
        #expect(status.metrics.configurationIssue == .invalidInterval)
        #expect(status.logs.configurationIssue == .invalidEndpoint)
        #expect(await service.configuration == configuration)
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("Partial acceptance retires the whole log batch and counts only reported rejections")
    func partialAcceptance() async throws {
        let clock = MonitoringManualExportClock()
        let transport = MonitoringRecordingTransport(responses: [
            exportResponse(body: #"{"partialSuccess":{"rejectedLogRecords":"1","errorMessage":"private"}}"#)
        ])
        let store = MonitoringStore()
        let service = MonitoringExportService(store: store, transportFactory: { _ in transport }, clock: clock)
        await service.configure(exportConfiguration())
        for _ in 0..<3 { await service.enqueue(.operation(.test)) }
        await clock.advance(by: .seconds(2))
        try await exportEventually { await service.status().logs.lastAccepted != nil }
        let status = await service.status().logs
        #expect(status.drops == [.partialRejection: 1])
        #expect(status.queuedCount == 0)
        #expect(status.warning == .partialRejection)
        await clock.advance(by: .seconds(10))
        #expect(await transport.calls.count == 1)
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("Test export sends both markers without increasing AI request counters")
    func syntheticTest() async throws {
        let metrics = MonitoringRecordingTransport()
        let logs = MonitoringRecordingTransport()
        let store = MonitoringStore()
        let service = MonitoringExportService(
            store: store,
            transportFactory: { $0 == .metrics ? metrics : logs },
            clock: MonitoringContinuousExportClock())
        await service.configure(exportConfiguration(metrics: true))
        let result = await service.testExport()
        #expect(result == .init(metrics: .accepted, logs: .accepted))
        #expect(await metrics.calls.count == 1)
        #expect(await logs.calls.count == 1)
        let metricCall = try #require(await metrics.calls.first)
        let logCall = try #require(await logs.calls.first)
        let metricText = try #require(String(bytes: metricCall.body, encoding: .utf8))
        let logText = try #require(String(bytes: logCall.body, encoding: .utf8))
        #expect(metricText.contains("littleswitch.monitoring.test"))
        #expect(logText.contains("monitoring.test"))
        #expect(await store.snapshot().families.contains { $0.name == .requests } == false)
        await service.shutdown(flushTimeout: .zero)
    }
}
