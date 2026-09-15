import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Monitoring coordinator transaction")
struct MonitoringCoordinatorTests {
    @Test("Apply persists local settings and preserves unrelated configuration")
    func applyAndDraft() async throws {
        let store = RecordingConfigurationStore(configuration: .init())
        let coordinator = makeCoordinator(store: store)
        let proposed = MonitoringConfiguration(exposeMetrics: false, exposeLogs: true)
        let pending = await coordinator.setMonitoringDraft(.init(configuration: proposed))
        #expect(pending.monitoringDraft?.configuration == proposed)
        #expect(store.saves.isEmpty)
        let result = try await coordinator.applyMonitoring(.init(configuration: proposed))
        #expect(result.configuration.monitoring == proposed)
        #expect(result.monitoringDraft == nil)
        #expect(store.configuration.monitoring == proposed)
        #expect(!result.monitoringApplying)
        await coordinator.shutdown()
    }

    @Test("Token rotations use new accounts and a failed save preserves the previous token")
    func credentialTransaction() async throws {
        let store = RecordingConfigurationStore(configuration: .init())
        let secrets = MemorySecretStore()
        let coordinator = makeCoordinator(store: store, secrets: secrets)
        let config = MonitoringConfiguration(metrics: .init(authentication: .bearer))
        let first = try await coordinator.applyMonitoring(
            .init(configuration: config, metricsCredential: .replace("first-synthetic")))
        let firstID = try #require(first.configuration.monitoring.metrics.credentialID)
        #expect(try secrets.read(account: .monitoring(firstID)) == "first-synthetic")
        store.failNextSave()
        await #expect(throws: MonitoringSettingsError.saveFailed) {
            _ = try await coordinator.applyMonitoring(
                .init(configuration: first.configuration.monitoring, metricsCredential: .replace("second-synthetic")))
        }
        #expect(store.configuration.monitoring.metrics.credentialID == firstID)
        #expect(try secrets.read(account: .monitoring(firstID)) == "first-synthetic")
        let second = try await coordinator.applyMonitoring(
            .init(configuration: first.configuration.monitoring, metricsCredential: .replace("second-synthetic")))
        let secondID = try #require(second.configuration.monitoring.metrics.credentialID)
        #expect(secondID != firstID)
        #expect(try secrets.read(account: .monitoring(firstID)) == nil)
        #expect(try secrets.read(account: .monitoring(secondID)) == "second-synthetic")
        let encoded = try JSONEncoder().encode(store.configuration)
        #expect(try !#require(String(data: encoded, encoding: .utf8)).contains("synthetic"))
        await coordinator.shutdown()
    }

    @Test("A failed settings save explains that the previous settings remain active")
    func saveFailureCopy() async throws {
        let store = RecordingConfigurationStore(configuration: .init())
        let coordinator = makeCoordinator(store: store)
        store.failNextSave()

        do {
            _ = try await coordinator.applyMonitoring(.init(configuration: .init()))
            Issue.record("The failed save should throw")
        } catch let error as MonitoringSettingsError {
            #expect(
                error.errorDescription
                    == L10n.string(
                        "Monitoring settings could not be saved. The previous settings remain active."
                    )
            )
        }
        await coordinator.shutdown()
    }

    private func makeCoordinator(
        store: RecordingConfigurationStore,
        secrets: MemorySecretStore = MemorySecretStore()
    ) -> ApplicationCoordinator {
        ApplicationCoordinator(
            configurationStore: store,
            secretStore: secrets,
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: TestGatewayTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
    }
}
