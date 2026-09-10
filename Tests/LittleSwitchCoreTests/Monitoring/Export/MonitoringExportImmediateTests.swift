import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring immediate test acknowledgements")
struct MonitoringExportImmediateTests {
    @Test("An immediate acknowledgement cannot overtake the test reservation")
    func immediateAcknowledgements() async throws {
        let transport = MonitoringRecordingTransport()
        let service = MonitoringExportService(
            store: .init(), transportFactory: { _ in transport }, logLimits: .init(maximumBatchEntries: 1))
        await service.configure(exportConfiguration())
        for expectedCount in 1...64 {
            let attempt = Task { await service.testExport() }
            try await exportEventually { await transport.calls.count == expectedCount }
            try await exportEventually { await service.status().isTesting == false }
            if await service.status().isTesting {
                await service.shutdown(flushTimeout: .zero)
                _ = await attempt.value
                return
            }
            #expect(await attempt.value.logs == .accepted)
        }
        #expect(await transport.maximumActiveCount == 1)
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("A test that cannot enter the bounded queue completes without waiting for an impossible send")
    func testQueuePressure() async {
        let transport = MonitoringRecordingTransport()
        let service = MonitoringExportService(
            store: .init(), transportFactory: { _ in transport }, logLimits: .init(maximumEntries: 0))
        await service.configure(exportConfiguration())
        #expect(await service.testExport().logs == .cancelled)
        #expect(await service.status().logs.drops == [.queueFull: 1])
        #expect(await transport.calls.isEmpty)
        await service.shutdown(flushTimeout: .zero)
    }
}
