import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Claude Desktop pending catalog polling")
struct ClaudeDesktopPendingPollingTests {
    @Test("Background catalog changes publish during monitoring work without replacing edits")
    func publishesWithoutReplacingDrafts() {
        let model = AppModel(snapshot: snapshot(pending: false, sequence: 1))
        model.configuration.autoMode = false
        model.hasPendingClaudeMappings = true
        model.isBusy = true
        model.monitoringAction = .apply
        let configuration = model.configuration

        update(pending: true, sequence: 2).apply(to: model)

        #expect(model.hasPendingClaudeDesktopChanges)
        #expect(model.configuration == configuration)
        #expect(model.hasPendingClaudeMappings)
        #expect(model.isBusy)
        #expect(model.monitoringAction == .apply)

        update(pending: false, sequence: 3).apply(to: model)
        #expect(!model.hasPendingClaudeDesktopChanges)
    }

    @Test("A poll captured before Apply cannot restore the completed catalog warning")
    func ignoresPollBeforeApply() {
        let model = AppModel(snapshot: snapshot(pending: true, sequence: 10))
        let stale = update(pending: true, sequence: 11)

        model.apply(snapshot(pending: false, sequence: 12))
        stale.apply(to: model)

        #expect(!model.hasPendingClaudeDesktopChanges)
        #expect(model.pendingChangesWarning == nil)
    }

    @Test("An older operation snapshot cannot hide a newer background catalog change")
    func ignoresOperationBeforePoll() {
        let model = AppModel(snapshot: snapshot(pending: false, sequence: 20))
        let stale = snapshot(pending: false, sequence: 21)
        update(pending: true, sequence: 22).apply(to: model)

        model.apply(stale)

        #expect(model.hasPendingClaudeDesktopChanges)
        #expect(model.pendingChangesWarning != nil)
    }

    private func snapshot(pending: Bool, sequence: UInt64) -> CoordinatorSnapshot {
        CoordinatorSnapshot(
            configuration: .init(),
            hasPendingClaudeDesktopChanges: pending,
            monitoringSnapshotSequence: sequence
        )
    }

    private func update(pending: Bool, sequence: UInt64) -> GatewayActivityPollingUpdate {
        GatewayActivityPollingUpdate(snapshot: snapshot(pending: pending, sequence: sequence), activity: .starting)
    }
}
