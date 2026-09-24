import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
struct ChatGPTLifecycleBoundaryTests {
    @Test func normalRelaunchRemovesOnlyInheritedManagedOverrides() async throws {
        let fixture = try await ChatGPTFixture.make(
            connected: true,
            environment: [
                "CODEX_API_BASE_URL": " \(ChatGPTLaunchEnvironment.apiBaseURL)\n",
                "CODEX_APP_SERVER_CHATGPT_BASE_URL": ChatGPTLaunchEnvironment.apiBaseURL,
                "TEST_PARENT": "inherited",
            ])
        _ = try await fixture.coordinator.disconnectChatGPT()
        #expect(fixture.controller.environments.last == ["TEST_PARENT": "inherited"])
        #expect(!fixture.store.configuration.chatgpt.connected)
        #expect(await !fixture.server.isRunning)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test func failedPrimaryStartupCannotDiscardUnreconciledCodexOwnershipOnQuit() async throws {
        var configuration = AppConfiguration()
        configuration.codex.connected = true
        configuration.chatgpt.connected = true
        let store = RecordingConfigurationStore(configuration: configuration)
        let events = SharedEventLog()
        let server = ChatGPTTestServer(events: events)
        await server.failNextStart()
        let controller = ChatGPTTestController(events: events)
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            codexController: controller,
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: server)
        await #expect(throws: CancellationError.self) { try await coordinator.start() }
        #expect(await !coordinator.shutdown())
        #expect(await coordinator.snapshot().chatGPTStatus == .needsAttention)
        #expect(store.configuration.codex.connected && store.configuration.chatgpt.connected)
        #expect(!events.recorded.contains("open-normal"))
        await coordinator.shutdown(mode: .handoff)
    }
    @Test func disconnectingAnAlreadyDisconnectedClientDoesNotRelaunchDesktop() async throws {
        let fixture = try await ChatGPTFixture.make()
        let before = await fixture.coordinator.snapshot()
        let after = try await fixture.coordinator.disconnectChatGPT()
        #expect(after.configuration == before.configuration)
        #expect(after.chatGPTStatus == .disconnected)
        #expect(fixture.events.recorded.isEmpty)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test func missingIdentityFailsBeforeTrustInstallationOrDesktopQuit() async throws {
        let fixture = try await ChatGPTFixture.make(hasIdentity: false)
        await #expect(throws: ChatGPTConnectionError.trustRequired) { try await fixture.coordinator.connectChatGPT() }
        #expect(fixture.events.recorded.isEmpty)
        #expect(await fixture.mainServer.isRunning)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test func shutdownWithoutControllerRetainsSavedConnectionResponsibility() async throws {
        let fixture = try await ChatGPTFixture.make(connected: true, hasController: false)
        #expect(await !fixture.coordinator.shutdown())
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .needsAttention)
        #expect(fixture.store.configuration.chatgpt.connected)
        #expect(await fixture.server.isRunning)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test(arguments: [false, true])
    func cancellationPropagatesIntoDesktopTransactions(disconnect: Bool) async throws {
        let fixture = try await ChatGPTFixture.make()
        if disconnect { _ = try await fixture.coordinator.connectChatGPT() }
        let entered = AsyncTestGate()
        let release = AsyncTestGate()
        fixture.controller.onQuit = {
            await entered.open()
            try? await release.wait()
        }
        let operation = Task {
            if disconnect { return try await fixture.coordinator.disconnectChatGPT() }
            return try await fixture.coordinator.connectChatGPT()
        }
        try await entered.wait(description: "desktop transaction entered quit")
        await #expect(throws: ChatGPTConnectionError.operationInProgress) {
            try await fixture.coordinator.connectCodex()
        }
        operation.cancel()
        await release.open()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(fixture.store.configuration.chatgpt.connected == disconnect)
        #expect(fixture.controller.running)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test func unavailableListenerDependenciesProduceARecoverableConnectionError() async {
        let coordinator = ApplicationCoordinator(
            configurationStore: RecordingConfigurationStore(configuration: .init()),
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport())
        await #expect(throws: ChatGPTConnectionError.unavailable) {
            try await coordinator.startChatGPTListener(installTrust: false)
        }
    }

    @Test func connectionErrorsProvideDistinctActionableDescriptions() {
        let errors: [ChatGPTConnectionError] = [
            .unavailable, .noModels, .pendingCodex, .trustRequired, .operationInProgress, .rollbackFailed,
            .conflictingEnvironment, .certificateBundleUnavailable,
        ]
        let descriptions = errors.compactMap(\.errorDescription)
        #expect(descriptions.count == errors.count)
        #expect(Set(descriptions).count == errors.count)
        #expect(descriptions.allSatisfy { !$0.isEmpty && !$0.contains("CODEX_API_BASE_URL") })
    }

    @Test func liveBuilderRejectsCorruptionAndDisposesItsIndependentListener() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "history.json")
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM, authorityPEM: issued.authorityPEM, keyPEM: issued.keyPEM)
        let fixture = try await ChatGPTFixture.make()
        let state = try #require(await fixture.coordinator.gatewayState)
        let monitoring = await fixture.coordinator.gatewayMonitoring
        let builder = LiveChatGPTGatewayBuilder(historyFileURL: file, trafficRecorder: NoopTrafficRecorder())
        let server = try builder.makeGateway(
            state: state, secretStore: MemorySecretStore(), identity: identity, monitoring: monitoring)
        #expect(await !server.isRunning)
        await server.stop()
        #expect(await fixture.mainServer.isRunning)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try Data("corrupt".utf8).write(to: file)
        #expect(throws: ChatGPTHistoryError.invalidStorage) {
            try builder.makeGateway(
                state: state, secretStore: MemorySecretStore(), identity: identity, monitoring: monitoring)
        }
        #expect(try Data(contentsOf: file) == Data("corrupt".utf8))
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
