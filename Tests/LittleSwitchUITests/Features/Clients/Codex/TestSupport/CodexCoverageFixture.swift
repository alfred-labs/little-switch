import Foundation
import LittleSwitchCore

@testable import LittleSwitchUI

@MainActor
struct CodexCoverageFixture {
    let providerID: UUID
    let applied: ModelMapping
    let replacement: ModelMapping
    let store: ScriptedConfigurationStore
    let profile: ScriptedCodexProfileManager
    let controller: ScriptedApplicationController
    let coordinator: ApplicationCoordinator

    static func make(
        connected: Bool = false,
        codexRunning: Bool = false,
        excludedModels: [ModelMapping] = [],
        includeDependencies: Bool = true,
        allModelsHidden: Bool = false
    ) async throws -> Self {
        let providerID = UUID()
        let applied = ModelMapping(providerID: providerID, modelID: "applied")
        let replacement = ModelMapping(providerID: providerID, modelID: "replacement")
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "applied"), DiscoveredModel(id: "replacement")],
            status: .ready
        )
        let configuration = AppConfiguration(
            providers: [provider],
            codex: CodexConfiguration(
                connected: connected,
                defaultModel: allModelsHidden ? nil : applied,
                excludedModels: allModelsHidden ? [applied, replacement] : excludedModels
            )
        )
        let store = ScriptedConfigurationStore(configuration: configuration)
        let profile = ScriptedCodexProfileManager(active: connected)
        let controller = ScriptedApplicationController(running: codexRunning)
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: ScriptedClaudeProfileManager(),
            claudeController: ScriptedApplicationController(),
            codexProfileManager: includeDependencies ? profile : nil,
            codexController: includeDependencies ? controller : nil,
            discoveryTransport: ScriptedCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
        _ = try await coordinator.start()
        return Self(
            providerID: providerID,
            applied: applied,
            replacement: replacement,
            store: store,
            profile: profile,
            controller: controller,
            coordinator: coordinator
        )
    }

    func stageLegacyAllHiddenDraft() async {
        let mappings = [applied, replacement]
        await coordinator.updateCodexDraft { @Sendable draft in
            draft.defaultModel = nil
            draft.excludedModels = mappings
        }
    }
}
