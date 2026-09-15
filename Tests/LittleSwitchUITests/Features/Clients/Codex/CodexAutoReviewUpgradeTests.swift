import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Codex custom reviewer upgrade")
struct CodexAutoReviewUpgradeTests {
    @Test("The previous reviewer catalog stays connected and exposes Apply in the menu", arguments: [false, true])
    func startupAndApply(failingSave: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "little-switch-review-upgrade-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = CodexProfilePaths(homeDirectory: root, applicationSupport: root.appending(path: "support"))
        try FileManager.default.createDirectory(
            at: paths.config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"models":[]}"#.utf8).write(
            to: paths.config.deletingLastPathComponent().appending(path: "models_cache.json"))
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "applied"), DiscoveredModel(id: "replacement")],
            status: .ready)
        let reviewer = ModelMapping(providerID: provider.id, modelID: "replacement")
        let configuration = AppConfiguration(
            providers: [provider],
            codex: CodexConfiguration(
                connected: true,
                defaultModel: ModelMapping(providerID: provider.id, modelID: "applied"),
                excludedModels: [reviewer],
                autoReviewModel: reviewer))
        let profile = CodexProfileManager(paths: paths)
        try profile.activate(providers: configuration.providers, configuration: configuration.codex)
        let currentCatalog = try String(contentsOf: paths.catalog, encoding: .utf8)
        let previousCatalog = currentCatalog.replacingOccurrences(
            of: "little-switch-auto-review", with: "codex-auto-review")
        try Data(previousCatalog.utf8).write(to: paths.catalog)
        let store = RecordingConfigurationStore(configuration: configuration)
        let codex = TestCodexController(running: true)
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: ScriptedClaudeProfileManager(),
            claudeController: TestClaudeController(),
            codexProfileManager: profile,
            codexController: codex,
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer())

        let startup = try await coordinator.start()
        #expect(startup.configuration.codex == configuration.codex)
        #expect(startup.hasPendingCodexChanges)
        #expect(store.configuration.codex == configuration.codex)
        #expect(codex.quitCount == 0)
        #expect(codex.openCount == 0)
        #expect(try String(contentsOf: paths.catalog, encoding: .utf8) == previousCatalog)
        let model = AppModel(snapshot: startup)
        let host = MenuControlTestHost(
            MenuCodexTabView(model: model, onDefault: { _ in }, onAutoReview: { _ in }, onApplyCodex: {}),
            height: MenuCodexTabView.height)
        defer { host.close() }
        try await host.activateAccessibility()
        #expect(try host.element(label: L10n.string("Apply changes")).isAccessibilityEnabled())

        if failingSave {
            store.failNextSave()
            await #expect(throws: RecordingConfigurationStore.Error.injected) {
                _ = try await coordinator.applyCodexSettings()
            }
            let rolledBack = await coordinator.snapshot()
            #expect(rolledBack.configuration == startup.configuration)
            #expect(rolledBack.hasPendingCodexChanges)
            #expect(try String(contentsOf: paths.catalog, encoding: .utf8) == previousCatalog)
        } else {
            let applied = try await coordinator.applyCodexSettings()
            #expect(applied.configuration == startup.configuration)
            #expect(!applied.hasPendingCodexChanges)
            #expect(try String(contentsOf: paths.catalog, encoding: .utf8) == currentCatalog)
        }
        await coordinator.shutdown(mode: .handoff)
    }
}
