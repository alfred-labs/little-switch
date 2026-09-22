import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Codex identifier profile upgrade")
struct CodexIdentifierUpgradeTests {
    @Test("Startup preserves a historical connected configuration until Apply", arguments: [false, true])
    func startupAndApply(failingSave: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "little-switch-identifier-upgrade-\(UUID())")
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
            models: [DiscoveredModel(id: "applied"), DiscoveredModel(id: "reviewer")],
            status: .ready,
            maximumParallelRequests: 7)
        let reviewer = ModelMapping(providerID: provider.id, modelID: "reviewer")
        let configuration = AppConfiguration(
            providers: [provider],
            codex: CodexConfiguration(
                connected: true,
                defaultModel: ModelMapping(providerID: provider.id, modelID: "applied"),
                excludedModels: [reviewer],
                autoReviewModel: reviewer))
        let profile = CodexProfileManager(paths: paths)
        try profile.activate(providers: configuration.providers, configuration: configuration.codex)
        let current = try paths.managedFiles.map { try Data(contentsOf: $0) }
        for path in [paths.config, paths.catalog] {
            let source = try String(contentsOf: path, encoding: .utf8)
            #expect(source.contains("local:applied"))
            try Data(source.replacingOccurrences(of: "local:applied", with: "local/applied").utf8).write(to: path)
        }
        let historical = try paths.managedFiles.map { try Data(contentsOf: $0) }
        let store = RecordingConfigurationStore(configuration: configuration)
        let codex = TestCodexController(running: true)
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: ScriptedClaudeProfileManager(),
            claudeController: TestClaudeController(),
            codexProfileManager: profile,
            codexController: codex,
            discoveryTransport: StaticCatalogTransport(catalogBody: #"{"data":[{"id":"applied"},{"id":"reviewer"}]}"#),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer())

        let startup = try await coordinator.start()
        #expect(startup.configuration.codex == configuration.codex)
        #expect(startup.hasPendingCodexChanges)
        #expect(store.configuration.codex == configuration.codex)
        #expect(codex.quitCount == 0)
        #expect(codex.openCount == 0)
        #expect(try paths.managedFiles.map { try Data(contentsOf: $0) } == historical)

        if failingSave {
            store.failNextSave()
            await #expect(throws: RecordingConfigurationStore.Error.injected) {
                _ = try await coordinator.applyCodexSettings()
            }
            let rolledBack = await coordinator.snapshot()
            #expect(rolledBack.configuration == startup.configuration)
            #expect(rolledBack.hasPendingCodexChanges)
            #expect(try paths.managedFiles.map { try Data(contentsOf: $0) } == historical)
        } else {
            let applied = try await coordinator.applyCodexSettings()
            #expect(applied.configuration == startup.configuration)
            #expect(!applied.hasPendingCodexChanges)
            #expect(try paths.managedFiles.map { try Data(contentsOf: $0) } == current)
        }
        await coordinator.shutdown(mode: .handoff)
    }
}
