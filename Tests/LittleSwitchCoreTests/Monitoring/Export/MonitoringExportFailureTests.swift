import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring controlled export failures")
struct MonitoringExportFailureTests {
    private struct Expected {
        let outcome: MonitoringExportTestOutcome
        let state: MonitoringExportState
        let warning: MonitoringExportWarning?
        let dropped: UInt64
    }

    @Test("A failed metric encoder resolves the test and records the affected points")
    func localEncodingFailure() async {
        let transport = MonitoringRecordingTransport()
        let service = MonitoringExportService(
            store: .init(),
            transportFactory: { _ in transport },
            encodeMetrics: { _ in throw OTLPMetricsEncoder.Failure.inconsistentMetric })
        await service.configure(exportConfiguration(metrics: true, logs: false))
        let result = await service.testExport()
        #expect(result.metrics == .failed(.invalidResponse))
        #expect(await service.status().metrics.drops == [.rejected: 1])
        #expect(await transport.calls.isEmpty)
        await service.shutdown(flushTimeout: .zero)
    }

    @Test("Receiver warnings are controlled and a partial test counts only its rejected records")
    func partialAndWarningTests() async {
        let cases: [(String, Expected)] = [
            (
                #"{"partialSuccess":{"errorMessage":"unsafe receiver text"}}"#,
                .init(outcome: .warning, state: .idle, warning: .receiverWarning, dropped: 0)
            ),
            (
                #"{"partialSuccess":{"rejectedLogRecords":1}}"#,
                .init(outcome: .partial(rejected: 1), state: .idle, warning: .partialRejection, dropped: 1)
            ),
        ]
        for (body, expected) in cases {
            let transport = MonitoringRecordingTransport(responses: [exportResponse(body: body)])
            let service = MonitoringExportService(
                store: .init(), transportFactory: { _ in transport }, clock: MonitoringContinuousExportClock())
            await service.configure(exportConfiguration())
            #expect(await service.testExport().logs == expected.outcome)
            let status = await service.status().logs
            #expect(status.warning == expected.warning)
            #expect(status.droppedCount == expected.dropped)
            #expect(status.lastAccepted != nil)
            await service.shutdown(flushTimeout: .zero)
        }
    }

    @Test("Transport exceptions remain controlled and cancellation is not retried")
    func transportFailures() async {
        let cases: [(URLError.Code, Expected)] = [
            (.networkConnectionLost, .init(outcome: .retrying(.network), state: .retrying, warning: nil, dropped: 0)),
            (.cancelled, .init(outcome: .cancelled, state: .idle, warning: nil, dropped: 1)),
        ]
        for (code, expected) in cases {
            let transport = MonitoringThrowingTransport(error: URLError(code))
            let service = MonitoringExportService(
                store: .init(), transportFactory: { _ in transport }, clock: MonitoringContinuousExportClock())
            await service.configure(exportConfiguration())
            #expect(await service.testExport().logs == expected.outcome)
            #expect(await service.status().logs.state == expected.state)
            #expect(await service.status().logs.droppedCount == expected.dropped)
            await service.shutdown(flushTimeout: .zero)
        }
    }

    @Test("Bearer validation occurs before a transport is constructed")
    func credentials() async {
        for token: String? in [nil, "", "invalid\nheader"] {
            let service = MonitoringExportService(store: .init())
            var configuration = exportConfiguration()
            configuration.logs.authentication = .bearer
            configuration.logs.credentialID = UUID()
            await service.configure(configuration, logsBearer: token)
            #expect(await service.status().logs.configurationIssue == .missingCredential)
            #expect(await service.testExport().logs == .invalidConfiguration(.missingCredential))
            await service.shutdown(flushTimeout: .zero)
        }
    }

    @Test("Shutdown cancels an active synthetic test and closes its owned send")
    func cancelActiveTest() async throws {
        let transport = MonitoringRecordingTransport()
        await transport.hold()
        let service = MonitoringExportService(
            store: .init(), transportFactory: { _ in transport }, clock: MonitoringContinuousExportClock())
        await service.configure(exportConfiguration())
        let testing = Task { await service.testExport() }
        try await exportEventually { await transport.activeCount == 1 }
        #expect(await service.status().isTesting)
        await service.shutdown(flushTimeout: .zero)
        #expect(await testing.value.logs == .cancelled)
        #expect(await service.status().isTesting == false)
        #expect(await transport.activeCount == 0)
        #expect(await service.testExport() == .init(metrics: .cancelled, logs: .cancelled))
    }
}
