import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Desktop application coordinator")
struct DesktopApplicationCoordinatorTests {
    @Test("A managed Desktop cannot be applied from Settings even with valid shared routing")
    func managedSettingsAction() {
        let provider = Provider(
            name: "Test",
            baseURL: "http://localhost:12345",
            authMode: .none,
            models: [DiscoveredModel(id: "model")]
        )
        let configuration = AppConfiguration(
            providers: [provider],
            mappings: ["claude-opus-5": ModelMapping(providerID: provider.id, modelID: "model")]
        )
        let model = AppModel(
            snapshot: CoordinatorSnapshot(configuration: configuration, claudeCodeMappedRouteIDs: ["claude-opus-5"]))
        model.desktopApplications = .init(claude: .available)
        #expect(model.canPerformClaudePrimaryAction)
        model.desktopApplications.claude = .organizationManaged
        #expect(!model.canPerformClaudePrimaryAction)
        #expect(model.canPerformClaudeCodePrimaryAction)
    }

    @Test("Managed Claude is rejected before changing profiles, configuration or gateway")
    func managedConnection() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigurationStore(
            fileURL: root.appending(path: "config.json"), backupDirectory: root.appending(path: "backups"))
        let original = AppConfiguration()
        try store.save(original)
        let profile = TestClaudeProfileManager()
        let controller = TestClaudeController(running: true)
        let gateway = TestGatewayServer()
        let manager = DesktopApplicationManager(
            locateApplication: { _ in URL(filePath: "/Applications/Test.app") },
            isClaudeOrganizationManaged: { true },
            openApplication: { _ in Issue.record("Managed Claude must not launch") }
        )
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: profile,
            claudeController: controller,
            desktopApplications: manager,
            discoveryTransport: TestGatewayTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: gateway
        )
        await #expect(throws: DesktopApplicationLaunchError.organizationManaged) {
            try await coordinator.connect()
        }
        await #expect(throws: DesktopApplicationLaunchError.organizationManaged) {
            try await coordinator.setAutoMode(!original.autoMode)
        }
        #expect(try store.load() == original)
        #expect(try !profile.isActive(autoMode: original.autoMode))
        #expect(profile.restoreCount == 0)
        #expect(controller.quitCount == 0)
        #expect(controller.openCount == 0)
        #expect(await !gateway.isRunning)
        await coordinator.shutdown()
    }

    @Test("Launching is independent of connection state and polling preserves drafts and busy state")
    func launchAndRefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigurationStore(
            fileURL: root.appending(path: "config.json"), backupDirectory: root.appending(path: "backups"))
        try store.save(AppConfiguration())
        var installed = true
        var opened: [URL] = []
        let url = URL(filePath: "/Applications/Codex.app")
        let manager = DesktopApplicationManager(
            locateApplication: { _ in installed ? url : nil },
            isClaudeOrganizationManaged: { false },
            openApplication: { opened.append($0) }
        )
        let controller = TestClaudeController()
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: controller,
            desktopApplications: manager,
            discoveryTransport: TestGatewayTransport(),
            gatewayTransport: TestGatewayTransport()
        )
        let before = await coordinator.snapshot()
        let model = AppModel(snapshot: before)
        #expect(model.desktopApplications == .init(claude: .available, codex: .available, openCode: .available))
        try await coordinator.openDesktopApplication(.codex)
        #expect(opened == [url])
        #expect(await coordinator.snapshot().configuration == before.configuration)
        #expect(try store.load() == before.configuration)
        #expect(controller.quitCount == 0)
        model.hasPendingClaudeMappings = true
        model.isBusy = true
        installed = false
        let snapshot = await coordinator.snapshot()
        GatewayActivityPollingUpdate(snapshot: snapshot, activity: .starting).apply(to: model)
        #expect(model.desktopApplications == .init())
        #expect(model.hasPendingClaudeMappings)
        #expect(model.isBusy)
        model.apply(before)
        for application in DesktopApplication.allCases {
            #expect(model.desktopApplications[application] == .available)
        }
        await coordinator.shutdown()
    }

    @Test("A headless coordinator reports unavailable apps and refuses launch")
    func noLauncher() async {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let coordinator = ApplicationCoordinator(
            configurationStore: ConfigurationStore(fileURL: root.appending(path: "config.json"), backupDirectory: root),
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: TestGatewayTransport(),
            gatewayTransport: TestGatewayTransport()
        )
        #expect(await coordinator.snapshot().desktopApplications == .init())
        await #expect(throws: DesktopApplicationLaunchError.notInstalled(.openCode)) {
            try await coordinator.openDesktopApplication(.openCode)
        }
        await coordinator.shutdown()
    }
}
