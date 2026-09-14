import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Monitoring mutation persistence boundary")
struct MonitoringPersistenceBoundaryTests {
    @Test("Startup can persist a disconnected profile while retaining invalid monitoring settings")
    func startupPreservesInvalidMonitoring() async throws {
        let original = AppConfiguration(
            connected: true,
            monitoring: .init(
                exposeLogs: true,
                metrics: .init(enabled: true, endpoint: "hand-edited-invalid"),
                metricIntervalSeconds: 0
            )
        )
        try await withCoordinator(configuration: original) { coordinator, store, _ in
            let snapshot = try await coordinator.start()
            var expected = original
            expected.connected = false
            #expect(snapshot.configuration == expected)
            #expect(try store.load() == expected)
            #expect(snapshot.monitoringStatus.metrics.configurationIssue == .invalidInterval)
        }
    }

    @Test("Invalid new monitoring settings are rejected before the real store writes or creates backups")
    func rejectedMonitoringMutation() async throws {
        try await withCoordinator(configuration: .init()) { coordinator, store, _ in
            let before = try Data(contentsOf: store.fileURL)
            await #expect(throws: MonitoringSettingsError.invalidInterval) {
                _ = try await coordinator.applyMonitoring(
                    .init(configuration: .init(metricIntervalSeconds: 0), metricsCredential: .replace("synthetic")))
            }
            #expect(try Data(contentsOf: store.fileURL) == before)
            #expect(try store.load() == AppConfiguration())
            #expect(!FileManager.default.fileExists(atPath: store.backupDirectory.path))
            #expect(await coordinator.snapshot().configuration.monitoring == .init())
        }
    }

    @Test("Core validation accepts a new bearer destination after its credential reference is staged")
    func stagedCredentialIsPersisted() async throws {
        try await withCoordinator(configuration: .init()) { coordinator, store, secrets in
            let result = try await coordinator.applyMonitoring(
                .init(
                    configuration: .init(
                        logs: .init(
                            enabled: true, endpoint: "https://receiver.example/v1/logs", authentication: .bearer)),
                    logsCredential: .replace("synthetic")
                )
            )
            let identifier = try #require(result.configuration.monitoring.logs.credentialID)
            #expect(try secrets.read(account: .monitoring(identifier)) == "synthetic")
            #expect(try store.load() == result.configuration)
        }
    }

    private func withCoordinator(
        configuration: AppConfiguration,
        operation: @MainActor (ApplicationCoordinator, ConfigurationStore, MemorySecretStore) async throws -> Void
    ) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(
            fileURL: directory.appending(path: "config.json"),
            backupDirectory: directory.appending(path: "backups")
        )
        try JSONEncoder().encode(configuration).write(to: store.fileURL)
        let secrets = MemorySecretStore()
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: secrets,
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: TestGatewayTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
        do {
            try await operation(coordinator, store, secrets)
        } catch {
            await coordinator.shutdown(mode: .handoff)
            throw error
        }
        await coordinator.shutdown(mode: .handoff)
    }
}
