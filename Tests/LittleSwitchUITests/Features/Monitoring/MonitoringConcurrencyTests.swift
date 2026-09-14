import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Monitoring coordinator concurrency")
struct MonitoringConcurrencyTests {
    @Test("Apply owns the transaction until the old transport joins and preserves a newer draft")
    func applySuspendedDuringTransportShutdown() async throws {
        let fixture = MonitoringConcurrencyFixture(suspendShutdown: true)
        try await fixture.withCleanup {
            var configuration = MonitoringConcurrencyFixture.enabledLogs
            configuration.logs.authentication = .bearer
            let first = try await fixture.coordinator.applyMonitoring(
                .init(configuration: configuration, logsCredential: .replace("old-synthetic")))
            let oldID = try #require(first.configuration.monitoring.logs.credentialID)
            var draft = MonitoringSettingsDraft(configuration: first.configuration.monitoring)
            draft.logsToken = "submitted-synthetic"
            let submitted = draft.input
            _ = await fixture.coordinator.setMonitoringDraft(draft.pending)
            let applying = fixture.own(Task { try await fixture.coordinator.applyMonitoring(submitted) })
            try await fixture.transport.shutdownStarted.wait(description: "old monitoring transport shutdown")
            let during = await fixture.coordinator.snapshot()
            #expect(during.monitoringApplying)
            #expect(during.monitoringSnapshotSequence > first.monitoringSnapshotSequence)
            #expect(try fixture.secrets.storage.read(account: .monitoring(oldID)) == "old-synthetic")
            #expect(fixture.persistence.configuration.monitoring.logs.credentialID != oldID)
            let eventsBeforeSecondApply = fixture.events.recorded
            let savesBeforeSecondApply = fixture.persistence.saves
            await #expect(throws: MonitoringSettingsError.busy) {
                try await fixture.beforeRelease(description: "reject a concurrent monitoring Apply") {
                    try await fixture.coordinator.applyMonitoring(
                        .init(
                            configuration: first.configuration.monitoring,
                            logsCredential: .replace("must-not-be-written")))
                }
            }
            #expect(fixture.events.recorded == eventsBeforeSecondApply)
            #expect(fixture.persistence.saves == savesBeforeSecondApply)
            let skippedTest = try await fixture.beforeRelease(description: "skip Test during Apply") {
                await fixture.coordinator.testMonitoringExport()
            }
            #expect(skippedTest.monitoringApplying)
            #expect(!skippedTest.monitoringStatus.isTesting)
            #expect(await fixture.transport.sendCount == 0)
            draft.logsToken = "newer-synthetic"
            draft.configuration.exposeLogs = true
            let pending = draft.pending
            let newer = await fixture.coordinator.setMonitoringDraft(pending)
            await fixture.transport.releaseAll()
            let applied = try await applying.value
            #expect(!applied.monitoringApplying)
            #expect(applied.monitoringDraft == pending)
            #expect(applied.monitoringSnapshotSequence > newer.monitoringSnapshotSequence)
            let newID = try #require(applied.configuration.monitoring.logs.credentialID)
            #expect(newID != oldID)
            #expect(try fixture.secrets.storage.read(account: .monitoring(oldID)) == nil)
            #expect(try fixture.secrets.storage.read(account: .monitoring(newID)) == "submitted-synthetic")
            let events = fixture.events.recorded
            let writeIndex = try #require(events.firstIndex(of: "write:\(newID.uuidString)"))
            let readIndex = try #require(events.firstIndex(of: "read:\(newID.uuidString)"))
            let saveIndex = try #require(events.firstIndex(of: "save:\(newID.uuidString)"))
            let finishedIndex = try #require(events.firstIndex(of: "shutdown-finished"))
            let deletionIndex = try #require(events.firstIndex(of: "delete:\(oldID.uuidString)"))
            #expect(writeIndex < readIndex)
            #expect(readIndex < saveIndex)
            #expect(saveIndex < finishedIndex)
            #expect(finishedIndex < deletionIndex)
            draft.acknowledge(applied.configuration.monitoring, submitted: submitted)
            #expect(draft.logsToken == "newer-synthetic")
            #expect(draft.configuration.exposeLogs)
            #expect(draft.configuration.logs.credentialID == newID)
        }
    }

    @Test("A suspended Test rejects Apply and a second Test without another send or I/O")
    func testOwnsTheExportIntent() async throws {
        let fixture = MonitoringConcurrencyFixture(suspendSend: true)
        try await fixture.withCleanup {
            let applied = try await fixture.coordinator.applyMonitoring(
                .init(configuration: MonitoringConcurrencyFixture.enabledLogs))
            let testing = fixture.own(Task { await fixture.coordinator.testMonitoringExport() })
            try await fixture.transport.sendStarted.wait(description: "synthetic monitoring send")
            let during = await fixture.coordinator.snapshot()
            #expect(during.monitoringStatus.isTesting)
            #expect(during.monitoringTestResult == nil)
            let eventsBeforeApply = fixture.events.recorded
            let savesBeforeApply = fixture.persistence.saves
            await #expect(throws: MonitoringSettingsError.busy) {
                try await fixture.beforeRelease(description: "reject Apply during a synthetic monitoring send") {
                    try await fixture.coordinator.applyMonitoring(
                        .init(configuration: .init(), metricsCredential: .replace("must-not-be-written")))
                }
            }
            #expect(fixture.events.recorded == eventsBeforeApply)
            #expect(fixture.persistence.saves == savesBeforeApply)
            let second = try await fixture.beforeRelease(description: "return a busy snapshot for a second Test") {
                await fixture.coordinator.testMonitoringExport()
            }
            #expect(second.monitoringStatus.isTesting)
            #expect(second.monitoringTestResult == nil)
            #expect(second.monitoringSnapshotSequence > during.monitoringSnapshotSequence)
            #expect(await fixture.transport.sendCount == 1)
            var pending = MonitoringPendingSettings(
                configuration: applied.configuration.monitoring, hasTypedToken: true)
            pending.configuration.exposeLogs = true
            let newer = await fixture.coordinator.setMonitoringDraft(pending)
            await fixture.transport.releaseAll()
            let completed = await testing.value
            #expect(completed.monitoringTestResult == .init(metrics: .disabled, logs: .accepted))
            #expect(!completed.monitoringStatus.isTesting)
            #expect(completed.monitoringDraft == pending)
            #expect(completed.monitoringSnapshotSequence > newer.monitoringSnapshotSequence)
            #expect(await fixture.transport.sendCount == 1)
            #expect(await !fixture.exporter.store.snapshot().families.contains { $0.name == .requests })
        }
    }

    @Test("Disabled exports and pending settings never create a synthetic test")
    func testRequiresAppliedEnabledDestination() async throws {
        let fixture = MonitoringConcurrencyFixture()
        try await fixture.withCleanup {
            let facade = await fixture.coordinator.gatewayMonitoring
            #expect(facade.store === fixture.exporter.store)
            #expect(await facade.configuration() == .init())
            await facade.recordLog(.operation(.gatewayStarted))
            let disabled = await fixture.coordinator.testMonitoringExport()
            #expect(disabled.monitoringTestResult == nil)
            let applied = try await fixture.coordinator.applyMonitoring(
                .init(configuration: MonitoringConcurrencyFixture.enabledLogs))
            #expect(await facade.configuration() == applied.configuration.monitoring)
            _ = await fixture.coordinator.setMonitoringDraft(
                .init(configuration: applied.configuration.monitoring, hasTypedToken: true))
            let pending = await fixture.coordinator.testMonitoringExport()
            #expect(pending.monitoringTestResult == nil)
            #expect(!pending.monitoringStatus.isTesting)
            #expect(pending.monitoringSnapshotSequence > disabled.monitoringSnapshotSequence)
            #expect(await fixture.transport.sendCount == 0)
            #expect(await !fixture.exporter.store.snapshot().families.contains { $0.name == .test })
        }
    }

    @Test("Startup restores an enabled saved bearer through the injected exporter")
    func startupReadsAppliedBearer() async throws {
        let identifier = UUID()
        let configuration = MonitoringConfiguration(
            logs: .init(
                enabled: true,
                endpoint: "https://receiver.example/v1/logs",
                authentication: .bearer,
                credentialID: identifier))
        let fixture = MonitoringConcurrencyFixture(configuration: configuration)
        try await fixture.withCleanup {
            try fixture.secrets.storage.write("saved-synthetic", account: .monitoring(identifier))
            let started = try await fixture.coordinator.start()
            #expect(started.configuration.monitoring == configuration)
            #expect(started.monitoringStatus.logs.state == .idle)
            #expect(fixture.events.recorded == ["read:\(identifier.uuidString)"])
            let tested = await fixture.coordinator.testMonitoringExport()
            #expect(tested.monitoringTestResult == .init(metrics: .disabled, logs: .accepted))
            #expect(await fixture.transport.sendCount == 1)
        }
    }

    @Test("An invalid interval is rejected before any configuration or credential access")
    func invalidIntervalBeforeIO() async throws {
        let fixture = MonitoringConcurrencyFixture()
        try await fixture.withCleanup {
            let invalid = MonitoringConfiguration(metricIntervalSeconds: 4)
            await #expect(throws: MonitoringSettingsError.invalidInterval) {
                _ = try await fixture.coordinator.applyMonitoring(
                    .init(configuration: invalid, metricsCredential: .replace("must-not-be-written")))
            }
            #expect(fixture.events.recorded.isEmpty)
            #expect(fixture.persistence.saves.isEmpty)
            #expect(await !fixture.coordinator.snapshot().monitoringApplying)
        }
    }

    @Test("Apply acknowledgement clears the submitted metrics token while preserving a newer logs token")
    func acknowledgeKeepsNewerLogsToken() {
        var draft = MonitoringSettingsDraft(configuration: .init())
        draft.metricsToken = "submitted-metrics"
        draft.logsToken = "submitted-logs"
        let submitted = draft.input
        draft.logsToken = "newer-logs"
        var applied = submitted.configuration
        applied.metrics.credentialID = UUID()
        applied.logs.credentialID = UUID()
        draft.acknowledge(applied, submitted: submitted)
        #expect(draft.metricsToken.isEmpty)
        #expect(draft.logsToken == "newer-logs")
        #expect(draft.configuration.metrics.credentialID == applied.metrics.credentialID)
        #expect(draft.configuration.logs.credentialID == applied.logs.credentialID)
    }
}
