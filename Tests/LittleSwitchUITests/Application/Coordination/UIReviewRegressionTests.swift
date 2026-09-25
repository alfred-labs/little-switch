import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("UI review state regressions")
struct UIReviewRegressionTests {
    enum CodexMutation: CaseIterable { case connect, apply, disconnect }
    enum OperationError: Swift.Error { case afterSave }

    @Test("A refused Codex quit prevents every profile mutation", arguments: CodexMutation.allCases)
    func refusedCodexQuit(_ mutation: CodexMutation) async throws {
        let fixture = try await CodexCoverageFixture.make(
            connected: mutation != .connect, codexRunning: true)
        if mutation == .apply {
            _ = try await fixture.coordinator.setCodexDefaultModel(fixture.replacement)
        }
        let before = await fixture.coordinator.snapshot()
        let persisted = fixture.store.configuration
        let activations = fixture.profile.activations
        let restores = fixture.profile.restoreCount
        fixture.controller.failQuits(on: [1])

        await #expect(throws: ScriptedApplicationController.Error.quitInjected) {
            switch mutation {
            case .connect: _ = try await fixture.coordinator.connectCodex()
            case .apply: _ = try await fixture.coordinator.applyCodexSettings()
            case .disconnect: _ = try await fixture.coordinator.disconnectDesktopClients()
            }
        }

        let after = await fixture.coordinator.snapshot()
        #expect(after.configuration == before.configuration)
        #expect(after.hasPendingCodexChanges == before.hasPendingCodexChanges)
        #expect(fixture.store.configuration == persisted)
        #expect(fixture.profile.activations == activations)
        #expect(fixture.profile.restoreCount == restores)
        #expect(fixture.controller.openAttempts == 0)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A failed operation republishes the state that was already committed")
    func partialFailureRefreshesPresentation() async throws {
        let fixture = try await CodexCoverageFixture.make()
        let delegate = LittleSwitchApplicationDelegate()
        delegate.coordinator = fixture.coordinator
        delegate.model.apply(await fixture.coordinator.snapshot())
        let target = !delegate.model.configuration.autoMode

        let success = await delegate.perform { coordinator in
            _ = try await coordinator.setAutoMode(target)
            throw OperationError.afterSave
        }

        #expect(!success)
        #expect(delegate.model.configuration == fixture.store.configuration)
        #expect(delegate.model.configuration.autoMode == target)
        #expect(!delegate.model.isBusy)
        #expect(delegate.model.errorMessage == delegate.startupErrorMessage(for: OperationError.afterSave))
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A failed web search apply keeps its pending state for the discard warning")
    func failedSearchApplyKeepsDraft() async throws {
        let fixture = try await CodexCoverageFixture.make()
        let input = WebSearchInput(
            configuration: .init(provider: .firecrawl), credential: "synthetic-key")
        _ = await fixture.coordinator.setWebSearchDraft(input.pendingSettings)
        fixture.store.failFutureSaves(at: [1])

        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.saveWebSearch(input)
        }

        let after = await fixture.coordinator.snapshot()
        #expect(after.webSearchDraft == input.pendingSettings)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Search edits publish before startup without blocking the initial authoritative snapshot")
    func searchDraftDuringStartup() {
        let delegate = LittleSwitchApplicationDelegate()
        let pending = WebSearchPendingSettings(configuration: .init(provider: .firecrawl))

        delegate.setWebSearchDraft(pending)

        #expect(delegate.model.webSearchDraft == pending)
        #expect(delegate.webSearchDraftTask == nil)

        delegate.model.apply(CoordinatorSnapshot(configuration: .init()))

        #expect(delegate.model.webSearchDraft == nil)
    }

    @Test("Search edits reach the coordinator in order and Apply waits for publication")
    func searchDraftPublicationAndApply() async throws {
        let fixture = try await CodexCoverageFixture.make()
        let delegate = LittleSwitchApplicationDelegate()
        delegate.coordinator = fixture.coordinator
        delegate.model.apply(await fixture.coordinator.snapshot())
        let first = WebSearchPendingSettings(configuration: .init(provider: .firecrawl, resultsLimit: 11))
        let input = WebSearchInput(
            configuration: .init(provider: .firecrawl, resultsLimit: 12), credential: "synthetic-key")
        delegate.setWebSearchDraft(first)
        delegate.setWebSearchDraft(input.pendingSettings)
        #expect(delegate.model.webSearchDraft == input.pendingSettings)

        let saved = await delegate.saveWebSearch(input)

        #expect(saved)
        #expect(delegate.model.configuration.webSearch == input.configuration)
        #expect(delegate.model.webSearchDraft == nil)
        #expect((await fixture.coordinator.snapshot()).webSearchDraft == nil)
        #expect(fixture.store.configuration.webSearch == input.configuration)
        #expect(!delegate.model.isBusy)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A failed provider mutation preserves both connected client drafts", arguments: [false, true])
    func failedProviderMutationPreservesDrafts(deleting: Bool) async throws {
        let fixture = try await ProviderDraftRollbackFixture.make()
        let before = await fixture.coordinator.snapshot()
        let persisted = fixture.store.configuration
        #expect(before.hasPendingClaudeCodeChanges)
        #expect(before.hasPendingOpenCodeChanges)
        fixture.store.failNextSave()
        await fixture.transport.serveCatalog(#"{"data":[{"id":"applied"}]}"#)

        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            if deleting {
                _ = try await fixture.coordinator.deleteProvider(id: fixture.providerID)
            } else {
                _ = try await fixture.coordinator.saveProvider(
                    ProviderInput(
                        id: fixture.providerID, name: "Beta", baseURL: "http://127.0.0.1:11435", authMode: .none))
            }
        }

        let after = await fixture.coordinator.snapshot()
        #expect(after.configuration == before.configuration)
        #expect(after.hasPendingClaudeCodeChanges)
        #expect(after.hasPendingOpenCodeChanges)
        #expect(fixture.store.configuration == persisted)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}

@MainActor
private struct ProviderDraftRollbackFixture {
    let providerID: UUID
    let store: RecordingConfigurationStore
    let transport: StaticCatalogTransport
    let coordinator: ApplicationCoordinator

    static func make() async throws -> Self {
        let alphaID = UUID()
        let betaID = UUID()
        let alpha = ModelMapping(providerID: alphaID, modelID: "applied")
        let beta = ModelMapping(providerID: betaID, modelID: "replacement")
        let providers = [(alphaID, "Alpha", 11_434), (betaID, "Beta", 11_435)].map { id, name, port in
            Provider(
                id: id,
                name: name,
                baseURL: "http://127.0.0.1:\(port)",
                authMode: .none,
                models: [DiscoveredModel(id: "applied"), DiscoveredModel(id: "replacement")],
                status: .ready)
        }
        let store = RecordingConfigurationStore(
            configuration: AppConfiguration(
                providers: providers,
                mappings: ["claude-sonnet-5": alpha, "claude-opus-5": beta],
                claudeCode: ClaudeCodeConfiguration(defaultModel: "claude-sonnet-5"),
                codex: CodexConfiguration(defaultModel: alpha),
                openCode: OpenCodeConfiguration(defaultModel: alpha)))
        let transport = StaticCatalogTransport()
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            claudeCodeProfileManager: TestClaudeCodeProfileManager(),
            openCodeProfileManager: TestOpenCodeProfileManager(),
            discoveryTransport: transport,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer())
        _ = try await coordinator.start()
        _ = try await coordinator.connectClaudeCode()
        _ = try await coordinator.connectOpenCode()
        _ = try await coordinator.setClaudeCodeDefaultModel("claude-opus-5")
        _ = try await coordinator.setOpenCodeDefaultModel(beta)
        return Self(providerID: betaID, store: store, transport: transport, coordinator: coordinator)
    }
}
