import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Monitoring transaction failure boundaries")
struct MonitoringTransactionFailureTests {
    @Test("Both destinations validate before any secret or configuration I/O")
    func validateBeforeWrites() async throws {
        let secrets = MonitoringSecretProbe()
        let persistence = RecordingConfigurationStore(configuration: .init())
        let coordinator = makeCoordinator(persistence, secrets: secrets)
        let proposed = MonitoringConfiguration(
            metrics: .init(enabled: true, endpoint: "https://metrics.example/v1/metrics"),
            logs: .init(enabled: true, endpoint: "http://remote.example/v1/logs")
        )
        await #expect(throws: MonitoringSettingsError.invalidEndpoint(.logs)) {
            _ = try await coordinator.applyMonitoring(
                .init(configuration: proposed, metricsCredential: .replace("synthetic"))
            )
        }
        #expect(secrets.events.recorded.isEmpty)
        #expect(persistence.saves.isEmpty)
        #expect(await coordinator.snapshot().configuration.monitoring == .init())
        #expect(await !coordinator.snapshot().monitoringApplying)
        await coordinator.shutdown()
    }

    @Test("A second secret write failure removes every staged account and preserves applied state")
    func secondWriteFails() async throws {
        let secrets = MonitoringSecretProbe(failingWrite: "fail-write")
        let persistence = RecordingConfigurationStore(configuration: .init())
        let coordinator = makeCoordinator(persistence, secrets: secrets)
        await #expect(throws: MonitoringSettingsError.credentialWriteFailed) {
            _ = try await coordinator.applyMonitoring(
                .init(
                    configuration: .init(),
                    metricsCredential: .replace("first-synthetic"),
                    logsCredential: .replace("fail-write")
                )
            )
        }
        let created = secrets.writtenIDs
        #expect(created.count == 2)
        for id in created { #expect(try secrets.storage.read(account: .monitoring(id)) == nil) }
        #expect(persistence.saves.isEmpty)
        #expect(await coordinator.snapshot().configuration.monitoring == .init())
        await coordinator.shutdown()
    }

    @Test("A missing or invalid saved bearer blocks activation without changing the reference")
    func invalidStoredToken() async throws {
        for token in ["", "invalid\nheader"] {
            let secrets = MonitoringSecretProbe()
            let persistence = RecordingConfigurationStore(configuration: .init())
            let coordinator = makeCoordinator(persistence, secrets: secrets)
            let saved = try await coordinator.applyMonitoring(
                .init(
                    configuration: .init(metrics: .init(authentication: .bearer)),
                    metricsCredential: .replace("synthetic")
                )
            )
            let id = try #require(saved.configuration.monitoring.metrics.credentialID)
            try secrets.storage.write(token, account: .monitoring(id))
            var proposed = saved.configuration.monitoring
            proposed.metrics.enabled = true
            proposed.metrics.endpoint = "https://metrics.example/v1/metrics"
            let expected: MonitoringSettingsError = token.isEmpty ? .missingToken(.metrics) : .invalidToken(.metrics)
            await #expect(throws: expected) {
                _ = try await coordinator.applyMonitoring(.init(configuration: proposed))
            }
            #expect(persistence.configuration.monitoring == saved.configuration.monitoring)
            #expect(secrets.writtenIDs == [id])
            await coordinator.shutdown()
        }
    }

    @Test("Removing a saved token is explicit; cleanup failure is reported after the configuration is applied")
    func removalAndCleanupNotice() async throws {
        let secrets = MonitoringSecretProbe(failDeletes: true)
        let persistence = RecordingConfigurationStore(configuration: .init())
        let coordinator = makeCoordinator(persistence, secrets: secrets)
        let saved = try await coordinator.applyMonitoring(
            .init(configuration: .init(), logsCredential: .replace("synthetic"))
        )
        let id = try #require(saved.configuration.monitoring.logs.credentialID)
        let removed = try await coordinator.applyMonitoring(
            .init(configuration: saved.configuration.monitoring, logsCredential: .remove)
        )
        #expect(removed.configuration.monitoring.logs.credentialID == nil)
        #expect(
            removed.monitoringNotice == L10n.string("An unused monitoring token could not be removed from Keychain."))
        #expect(try secrets.storage.read(account: .monitoring(id)) == "synthetic")
        await coordinator.shutdown()
    }

    @Test("Startup does not read tokens belonging to disabled or unauthenticated exports")
    func disabledCredentialReads() async throws {
        let configuration = MonitoringConfiguration(
            metrics: .init(authentication: .bearer, credentialID: UUID()),
            logs: .init(credentialID: UUID())
        )
        let secrets = MonitoringSecretProbe()
        let persistence = RecordingConfigurationStore(configuration: .init(monitoring: configuration))
        let coordinator = makeCoordinator(persistence, secrets: secrets)
        let snapshot = try await coordinator.start()
        #expect(snapshot.configuration.monitoring == configuration)
        #expect(secrets.events.recorded.isEmpty)
        #expect(snapshot.monitoringStatus == .init())
        await coordinator.shutdown()
    }

    private func makeCoordinator(
        _ store: RecordingConfigurationStore,
        secrets: MonitoringSecretProbe
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

private struct MonitoringSecretProbe: SecretStore {
    enum Failure: Error { case injected }
    let storage = MemorySecretStore()
    let events = SharedEventLog()
    var failingWrite: String?
    var failDeletes = false

    var writtenIDs: [UUID] {
        events.recorded.filter { $0.hasPrefix("write:") }.compactMap { UUID(uuidString: String($0.dropFirst(6))) }
    }

    func read(account: SecretAccount) throws -> String? {
        if case .monitoring = account { events.append("read") }
        return try storage.read(account: account)
    }

    func write(_ secret: String, account: SecretAccount) throws {
        if case .monitoring(let id) = account { events.append("write:\(id.uuidString)") }
        try storage.write(secret, account: account)
        if secret == failingWrite { throw Failure.injected }
    }

    func delete(account: SecretAccount) throws {
        if failDeletes { throw Failure.injected }
        try storage.delete(account: account)
    }
}
