import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring exporter batch acknowledgements")
struct MonitoringExportBatchTests {
    @Test("A metric test waits for the fragment that contains its synthetic gauge")
    func testMarkerAcknowledgement() async throws {
        let clock = MonitoringManualExportClock()
        let store = MonitoringStore()
        for _ in 0..<1_200 {
            await store.finish(
                .init(
                    requestID: UUID(),
                    finishedAt: Date(),
                    durationSeconds: 1,
                    client: .codex,
                    route: .responses,
                    outcome: .success,
                    providerID: UUID(),
                    statusCode: 200))
        }
        _ = await store.markTest()
        let snapshot = await store.snapshot(at: clock.now().date)
        let batches = try OTLPMetricsEncoder.batches(snapshot)
        #expect(batches.payloads.count > 1)
        let marker = Data(#""name":"littleswitch.monitoring.test""#.utf8)
        let replies = batches.payloads.map { payload in
            let markerRange = payload.body.range(of: marker)
            return exportResponse(markerRange == nil ? 200 : 401)
        }
        #expect(replies.first?.status == 200)
        let transport = MonitoringRecordingTransport(responses: replies)
        let service = MonitoringExportService(store: store, transportFactory: { _ in transport }, clock: clock)
        await service.configure(exportConfiguration(metrics: true, logs: false))
        let result = await service.testExport()
        #expect(result.metrics == .failed(.httpStatus(401)))
        #expect(await transport.calls.allSatisfy { $0.body.count <= 512 * 1_024 })
        #expect(await transport.maximumActiveCount == 1)
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("A second shutdown call joins the same in-progress shutdown")
    func repeatedShutdownJoins() async throws {
        let transport = MonitoringRecordingTransport()
        await transport.hold()
        let store = MonitoringStore()
        _ = await store.markTest()
        let service = MonitoringExportService(
            store: store, transportFactory: { _ in transport }, clock: MonitoringContinuousExportClock())
        await service.configure(exportConfiguration(metrics: true, logs: false))
        let first = Task { await service.shutdown(flushTimeout: .milliseconds(50)) }
        try await exportEventually { await transport.activeCount == 1 }
        await service.shutdown(flushTimeout: .zero)
        #expect(await transport.activeCount == 0)
        #expect(await transport.shutdownCount == 1)
        await first.value
    }

    @Test("The flush threshold is 256 events even before two seconds have elapsed")
    func thresholdFlush() async throws {
        let clock = MonitoringManualExportClock()
        let transport = MonitoringRecordingTransport()
        let service = MonitoringExportService(store: .init(), transportFactory: { _ in transport }, clock: clock)
        await service.configure(exportConfiguration())
        for _ in 0..<255 { await service.enqueue(.operation(.test)) }
        #expect(await transport.calls.isEmpty)
        await service.enqueue(.operation(.test))
        try await exportEventually { await service.status().logs.lastAccepted != nil }
        #expect(await transport.calls.count == 1)
        #expect(await service.status().logs.queuedCount == 0)
        await service.shutdown(flushTimeout: .zero)
    }
}
