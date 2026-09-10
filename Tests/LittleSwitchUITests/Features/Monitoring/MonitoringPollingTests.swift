import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Monitoring live presentation")
struct MonitoringPollingTests {
    @Test("A delayed poll cannot release a locally running Apply")
    func staleBusyPoll() {
        let model = AppModel()
        let old = GatewayActivityPollingUpdate(snapshot: .init(configuration: .init()), activity: .unavailable)
        model.monitoringApplying = true
        model.monitoringAction = .apply
        old.apply(to: model)
        #expect(model.monitoringApplying)
    }

    @Test("Older status from the same destination cannot erase a completed test")
    func staleTestPoll() {
        let model = AppModel()
        let old = GatewayActivityPollingUpdate(
            snapshot: .init(configuration: .init(), monitoringSnapshotSequence: 3), activity: .unavailable)
        let result = MonitoringExportTestResult(metrics: .accepted, logs: .disabled)
        model.apply(.init(configuration: .init(), monitoringTestResult: result, monitoringSnapshotSequence: 4))
        old.apply(to: model)
        #expect(model.monitoringTestResult == result)
        #expect(model.monitoringSnapshotSequence == 4)
        model.monitoringAction = .test
        model.monitoringStatus.isTesting = true
        old.apply(to: model)
        #expect(model.monitoringStatus.isTesting)
    }

    @Test("A poll from an old destination cannot restore its old test result")
    func staleDestinationPoll() {
        let model = AppModel()
        let old = GatewayActivityPollingUpdate(
            snapshot: .init(configuration: .init(), monitoringTestResult: .init(metrics: .accepted, logs: .disabled)),
            activity: .unavailable
        )
        let configuration = MonitoringConfiguration(
            metrics: .init(enabled: true, endpoint: "https://new.example/v1/metrics"))
        model.apply(.init(configuration: .init(monitoring: configuration)))
        old.apply(to: model)
        #expect(model.monitoringTestResult == nil)
    }

    @Test("Polling updates export state without replacing configuration or pending edits")
    func statusPolling() {
        let model = AppModel()
        var pending = MonitoringConfiguration()
        pending.metrics.endpoint = "https://receiver.example/v1/metrics"
        model.monitoringDraft = .init(configuration: pending)
        let current = model.configuration
        let status = MonitoringExportStatus(
            metrics: .init(state: .sending),
            logs: .init(state: .retrying, queuedCount: 12, queuedBytes: 700),
            isTesting: true
        )
        let result = MonitoringExportTestResult(metrics: .accepted, logs: .retrying(.network))
        let snapshot = CoordinatorSnapshot(
            configuration: current,
            monitoringStatus: status,
            monitoringApplying: true,
            monitoringNotice: "Synthetic cleanup notice",
            monitoringTestResult: result
        )
        GatewayActivityPollingUpdate(snapshot: snapshot, activity: .unavailable).apply(to: model)
        #expect(model.monitoringStatus == status)
        #expect(model.monitoringApplying)
        #expect(model.monitoringNotice == snapshot.monitoringNotice)
        #expect(model.monitoringTestResult == result)
        #expect(model.configuration == current)
        #expect(model.monitoringDraft?.configuration == pending)
        #expect(model.pendingChangeNames == ["Monitoring"])
    }
}
