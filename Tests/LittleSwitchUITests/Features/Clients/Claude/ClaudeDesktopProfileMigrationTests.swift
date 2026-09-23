import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Claude Desktop profile migration")
struct ClaudeDesktopProfileMigrationTests {
    @Test("Startup keeps ownership of an old profile so normal quit can restore Claude")
    func legacyConnectedProfileRestoresOnQuit() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-desktop-migration-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ClaudeProfilePaths(applicationSupport: root)
        let store = ConfigurationStore(
            fileURL: paths.littleSwitchConfig,
            backupDirectory: root.appending(path: "ConfigurationBackups")
        )
        let provider = Provider(
            name: "Synthetic",
            baseURL: "https://example.invalid",
            authMode: .none,
            models: [DiscoveredModel(id: "applied")],
            status: .ready
        )
        try store.save(
            AppConfiguration(
                providers: [provider],
                mappings: ["claude-opus-5": ModelMapping(providerID: provider.id, modelID: "applied")],
                connected: true
            )
        )
        let profileStore = DiskClaudeProfileFileStore(backupDirectory: paths.backupDirectory)
        let profile = ClaudeProfileManager(paths: paths, fileStore: profileStore)
        try profile.activate(autoMode: true, tlsEnabled: false)
        var legacy = try profileStore.readObject(paths.profile)
        legacy.removeValue(forKey: "modelDiscoveryEnabled")
        legacy.removeValue(forKey: "inferenceModels")
        try profileStore.writeObject(legacy, to: paths.profile)
        let legacyBytes = try Data(contentsOf: paths.profile)
        let controller = TestClaudeController(running: true)
        let gateway = TestGatewayServer()
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: profile,
            claudeController: controller,
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: gateway
        )

        let started = try await coordinator.start()

        #expect(started.configuration.connected)
        #expect(started.hasPendingClaudeDesktopChanges)
        #expect(try Data(contentsOf: paths.profile) == legacyBytes)
        #expect(try store.load().connected)
        #expect(controller.quitCount == 0)
        #expect(controller.openCount == 0)

        await coordinator.shutdown()

        #expect(try !store.load().connected)
        #expect(try profileStore.readObject(paths.normalConfig)["deploymentMode"] as? String == "1p")
        #expect(try profileStore.readObject(paths.thirdPartyConfig)["deploymentMode"] as? String == "1p")
        #expect(try profileStore.readObject(paths.metadata)["appliedId"] == nil)
        #expect(try profileStore.readObject(paths.profile)["inferenceGatewayBaseUrl"] == nil)
        #expect(await !gateway.isRunning)
    }
}
