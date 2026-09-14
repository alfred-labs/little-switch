import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Monitoring non-secret pending state")
struct MonitoringDraftRetentionTests {
    @Test("Token removal survives navigation while a typed replacement is cleared")
    func navigation() {
        var draft = MonitoringSettingsDraft(configuration: .init())
        draft.removeMetricsToken = true
        draft.logsToken = "synthetic"
        #expect(draft.pending.hasTypedToken)
        draft.clearTypedTokens()
        let restored = MonitoringSettingsDraft(configuration: .init(), pending: draft.pending)
        #expect(restored.input.metricsCredential == .remove)
        #expect(restored.input.logsCredential == .keep)
        #expect(!restored.pending.hasTypedToken)
        #expect(!restored.pending.matches(.init()))
    }

    @Test("A token-only edit participates in the application's discard warning without retaining the token")
    func discardWarning() async {
        let coordinator = ApplicationCoordinator(
            configurationStore: RecordingConfigurationStore(configuration: .init()),
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: TestGatewayTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
        let pending = MonitoringPendingSettings(configuration: .init(), hasTypedToken: true)
        let model = AppModel(snapshot: await coordinator.setMonitoringDraft(pending))
        #expect(model.pendingChangesWarning == "Unapplied changes for Monitoring will be discarded.")
        #expect(model.monitoringDraft == pending)
        model.apply(await coordinator.setMonitoringDraft(.init(configuration: .init())))
        #expect(!model.hasPendingChanges)
        await coordinator.shutdown()
    }
}
