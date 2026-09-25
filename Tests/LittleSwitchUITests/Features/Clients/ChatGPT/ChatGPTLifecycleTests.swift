import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("ChatGPT connection lifecycle")
struct ChatGPTLifecycleTests {
    @Test("Connect starts HTTPS before relaunch and commits only after opening")
    func connect() async throws {
        let fixture = try await ChatGPTFixture.make()
        let result = try await fixture.coordinator.connectChatGPT()
        #expect(result.configuration.chatgpt.connected)
        #expect(result.chatGPTStatus == .connected)
        #expect(fixture.events.recorded == ["trust", "start", "quit", "open-managed"])
        #expect(fixture.controller.environments.last?["TEST_PARENT"] == "inherited")
        #expect(fixture.store.configuration.chatgpt.connected)
        #expect(await fixture.mainServer.isRunning)
        _ = await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A failed save restores normal launch and stops only the ChatGPT listener")
    func saveRollback() async throws {
        let fixture = try await ChatGPTFixture.make()
        fixture.store.failNextSave()
        await #expect(throws: (any Error).self) { try await fixture.coordinator.connectChatGPT() }
        #expect(!fixture.store.configuration.chatgpt.connected)
        #expect(await fixture.mainServer.isRunning)
        #expect(await !fixture.server.isRunning)
        #expect(fixture.events.recorded == ["trust", "start", "quit", "open-managed", "quit", "open-normal", "stop"])
        _ = await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Startup recovers its listener without desktop relaunch or trust consent")
    func startup() async throws {
        let fixture = try await ChatGPTFixture.make(connected: true)
        #expect(fixture.events.recorded == ["start"])
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .ready)
        _ = await fixture.coordinator.shutdown(mode: .handoff)
        #expect(fixture.store.configuration.chatgpt.connected)
    }
}

@MainActor
struct ChatGPTFixture {
    let coordinator: ApplicationCoordinator
    let store: RecordingConfigurationStore
    let controller: ChatGPTTestController
    let codexProfile: TestCodexProfileManager
    let server: ChatGPTTestServer
    let mainServer: TestGatewayServer
    let events: SharedEventLog
    let builder: ChatGPTTestBuilder
    let certificates: ChatGPTTestCertificateDirectory
    let authorityPEM: String

    static func make(
        connected: Bool = false,
        trusted: Bool = true,
        hasIdentity: Bool = true,
        hasModels: Bool = true,
        hasChatModel: Bool = true,
        hasCodexExposure: Bool = true,
        hasController: Bool = true,
        failListenerStart: Bool = false,
        environment: [String: String] = ["TEST_PARENT": "inherited"]
    ) async throws -> Self {
        let events = SharedEventLog()
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "applied")],
            status: .ready
        )
        var configuration = AppConfiguration(providers: hasModels ? [provider] : [])
        configuration.chatgpt.connected = connected
        if hasChatModel {
            configuration.chatgpt.model = ModelMapping(providerID: provider.id, modelID: "applied")
        }
        if !hasCodexExposure {
            configuration.codex.excludedModels = ["applied", "replacement"].map {
                ModelMapping(providerID: provider.id, modelID: $0)
            }
        }
        let store = RecordingConfigurationStore(configuration: configuration)
        let controller = ChatGPTTestController(events: events)
        let codexProfile = TestCodexProfileManager()
        let server = ChatGPTTestServer(events: events)
        if failListenerStart { await server.failNextStart() }
        let mainServer = TestGatewayServer()
        let builder = ChatGPTTestBuilder(server: server)
        let certificates = ChatGPTTestCertificateDirectory()
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            codexProfileManager: codexProfile,
            codexController: hasController ? controller : nil,
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: mainServer,
            tlsProvisioner: ChatGPTTestTrust(identity: hasIdentity ? identity : nil, trusted: trusted, events: events),
            chatGPTGatewayBuilder: builder,
            chatGPTLaunchTrust: ChatGPTLaunchTrust(directory: certificates.url),
            inheritedEnvironment: environment
        )
        _ = try await coordinator.start()
        return Self(
            coordinator: coordinator,
            store: store,
            controller: controller,
            codexProfile: codexProfile,
            server: server,
            mainServer: mainServer,
            events: events,
            builder: builder,
            certificates: certificates,
            authorityPEM: issued.authorityPEM
        )
    }
}

actor ChatGPTTestServer: GatewayServing {
    let events: SharedEventLog
    var isRunning = false
    var failStart = false
    var onStop: (@Sendable () async -> Void)?
    func setOnStop(_ action: @escaping @Sendable () async -> Void) { onStop = action }
    func failNextStart() { failStart = true }
    init(events: SharedEventLog) { self.events = events }
    func start() async throws {
        events.append("start")
        if failStart { throw CancellationError() }
        isRunning = true
    }
    func stop() async {
        events.append("stop")
        await onStop?()
        isRunning = false
    }
}

struct ChatGPTTestTrust: GatewayTLSProvisioning {
    let identity: GatewayTLSIdentity?
    let trusted: Bool
    let events: SharedEventLog
    func identity(secretStore: any SecretStore) -> GatewayTLSIdentity? { identity }
    func isTrusted(secretStore: any SecretStore) -> Bool { trusted }
    func installTrust(secretStore: any SecretStore) -> GatewayTLSTrustOutcome {
        events.append("trust")
        return .init(isTrusted: trusted)
    }
    func revokeTrust(secretStore: any SecretStore) -> [GatewayTLSTrustFailure] {
        Issue.record("ChatGPT must preserve shared TLS trust")
        return []
    }
}

@MainActor
final class ChatGPTTestController: CodexApplicationControlling {
    let events: SharedEventLog
    var running = true
    var launchID = UUID()
    var failQuit = false
    var failOpen = false
    var onQuit: (@MainActor () async throws -> Void)?
    var onOpen: (@MainActor ([String: String]) async -> Void)?
    var environments: [[String: String]] = []
    init(events: SharedEventLog) { self.events = events }
    func isRunning() -> Bool { running }
    func isRunning(launchID: UUID) -> Bool { running && self.launchID == launchID }
    func openTracked(environment: [String: String]) async throws -> UUID {
        try await open(environment: environment)
        return launchID
    }
    func quitAndWait() async throws {
        try await onQuit?()
        if failQuit { throw CancellationError() }
        events.append("quit")
        running = false
    }
    func open() async throws { try await open(environment: [:]) }
    func open(environment: [String: String]) async throws {
        await onOpen?(environment)
        environments.append(environment)
        if failOpen {
            failOpen = false
            throw CancellationError()
        }
        events.append(environment["CODEX_API_BASE_URL"] == nil ? "open-normal" : "open-managed")
        running = true
        launchID = UUID()
    }
}
