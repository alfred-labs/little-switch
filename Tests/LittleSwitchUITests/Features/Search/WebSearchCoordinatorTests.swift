import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchSearch
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Web search coordinator")
struct WebSearchCoordinatorTests {
    @Test("A draft is kept only while it differs, and an apply clears it")
    func draftLifecycle() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make()
        defer { fixture.removeFiles() }
        let saved = await fixture.coordinator.snapshot().configuration.webSearch

        let clean = await fixture.coordinator.setWebSearchDraft(
            WebSearchPendingSettings(configuration: saved)
        )
        #expect(clean.webSearchDraft == nil)

        let draft = WebSearchInput(
            configuration: WebSearchConfiguration(provider: .firecrawl, resultsLimit: 12),
            credential: "firecrawl-key"
        )
        let pending = await fixture.coordinator.setWebSearchDraft(draft.pendingSettings)
        #expect(pending.webSearchDraft == draft.pendingSettings)

        let applied = try await fixture.coordinator.saveWebSearch(draft)
        #expect(applied.webSearchDraft == nil)
        #expect(applied.configuration.webSearch.resultsLimit == 12)

        _ = await fixture.coordinator.setWebSearchDraft(draft.pendingSettings)
        let cleared = await fixture.coordinator.setWebSearchDraft(nil)
        #expect(cleared.webSearchDraft == nil)
    }

    @Test("Connected saves persist Firecrawl and update the live gateway immediately")
    func connectedSave() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make()
        defer { fixture.removeFiles() }
        let configuration = WebSearchConfiguration(
            provider: .firecrawl,
            resultsLimit: 25,
            maximumUses: 4
        )

        let saved = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: configuration, credential: "firecrawl-key")
        )

        #expect(saved.configuration.webSearch == configuration)
        #expect((try fixture.store.load()).webSearch == configuration)
        #expect(await fixture.gatewayState.capture().webSearch == configuration)
        #expect(
            try fixture.secrets.read(account: .webSearch(.firecrawl))
                == "firecrawl-key"
        )
        #expect(fixture.controller.quitCount == 0)
        #expect(fixture.controller.openCount == 0)
    }

    @Test("Cloud requires a new or existing credential")
    func cloudCredentialRequired() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make()
        defer { fixture.removeFiles() }

        await #expect(throws: ApplicationCoordinator.Error.missingFirecrawlCredential) {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(configuration: .firecrawlCloud)
            )
        }
        #expect((try fixture.store.load()).webSearch == .disabled)
    }

    @Test("A disabled provider saves with no credential at all")
    func disabledSaveNeedsNoCredential() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make(
            existingCredential: "existing-key"
        )
        defer { fixture.removeFiles() }

        let saved = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: .disabled)
        )

        #expect(saved.configuration.webSearch == .disabled)
        #expect((try fixture.store.load()).webSearch == .disabled)
        #expect(await fixture.gatewayState.capture().webSearch == .disabled)
    }

    @Test("Blank Cloud input preserves an existing key")
    func preservedCloudCredential() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make(
            existingCredential: "existing-key"
        )
        defer { fixture.removeFiles() }

        _ = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: .firecrawlCloud, credential: "  ")
        )
        #expect((try fixture.store.load()).webSearch == .firecrawlCloud)
        #expect(
            try fixture.secrets.read(account: .webSearch(.firecrawl))
                == "existing-key"
        )
    }

    @Test("A failed blank Cloud save does not rewrite the preserved credential")
    func preservedCloudCredentialSaveFailure() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make(
            existingCredential: "existing-key"
        )
        defer { fixture.removeFiles() }
        let before = try fixture.store.load()
        fixture.store.failNextSave()
        fixture.secrets.failNextWrite()

        await #expect(throws: FailNextConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(configuration: .firecrawlCloud, credential: "  ")
            )
        }

        #expect((await fixture.coordinator.snapshot()).configuration == before)
        #expect(try fixture.store.load() == before)
        #expect(await fixture.gatewayState.capture().webSearch == before.webSearch)
        #expect(fixture.secrets.value(for: .webSearch(.firecrawl)) == "existing-key")
    }

    @Test("A failed first-time save restores an absent credential")
    func firstSaveRollbackWithoutStoredCredential() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make()
        defer { fixture.removeFiles() }
        fixture.store.failNextSave()

        await #expect(throws: FailNextConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(
                    configuration: WebSearchConfiguration(provider: .firecrawl),
                    credential: "new-key"
                )
            )
        }

        #expect(try fixture.secrets.read(account: .webSearch(.firecrawl)) == nil)
        #expect((try fixture.store.load()).webSearch == .disabled)
    }

    @Test("Invalid self-hosted URLs and each web search limit are rejected")
    func invalidConfiguration() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make()
        defer { fixture.removeFiles() }

        await #expect(throws: ApplicationCoordinator.Error.invalidWebSearchConfiguration) {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(
                    configuration: WebSearchConfiguration(resultsLimit: 101),
                    credential: "key"
                )
            )
        }
        await #expect(throws: ApplicationCoordinator.Error.invalidWebSearchConfiguration) {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(
                    configuration: WebSearchConfiguration(maximumUses: 11),
                    credential: "key"
                )
            )
        }
        #expect((try fixture.store.load()).webSearch == .disabled)
        #expect(
            ApplicationCoordinator.Error.invalidWebSearchConfiguration.errorDescription
                == L10n.string("Check the web search limits.")
        )
    }

    @Test("A failed configuration save restores memory, disk, key, and live routing")
    func saveRollback() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make(
            webSearch: .firecrawlCloud,
            existingCredential: "old-key"
        )
        defer { fixture.removeFiles() }
        let before = try fixture.store.load()
        fixture.store.failNextSave()

        await #expect(throws: FailNextConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(
                    configuration: WebSearchConfiguration(provider: .firecrawl),
                    credential: "new-key"
                )
            )
        }

        #expect((await fixture.coordinator.snapshot()).configuration == before)
        #expect(try fixture.store.load() == before)
        #expect(await fixture.gatewayState.capture().webSearch == before.webSearch)
        #expect(
            try fixture.secrets.read(account: .webSearch(.firecrawl))
                == "old-key"
        )
    }

    @Test("A failed restoration of an absent credential reports an incomplete rollback")
    func absentCredentialRollbackFailure() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make(
            webSearch: .firecrawlCloud
        )
        defer { fixture.removeFiles() }
        let before = try fixture.store.load()
        fixture.store.failNextSave()
        fixture.secrets.failNextDelete()

        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(
                    configuration: WebSearchConfiguration(provider: .firecrawl),
                    credential: "new-key"
                )
            )
        }

        #expect((await fixture.coordinator.snapshot()).configuration == before)
        #expect(try fixture.store.load() == before)
        #expect(await fixture.gatewayState.capture().webSearch == before.webSearch)
        #expect(fixture.secrets.value(for: .webSearch(.firecrawl)) == "new-key")
    }

    @Test("A failed replacement rollback reports the credential's final known state")
    func replacementRollbackFailure() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make(
            webSearch: .firecrawlCloud,
            existingCredential: "old-key"
        )
        defer { fixture.removeFiles() }
        let before = try fixture.store.load()
        fixture.store.failNextSave()
        fixture.secrets.failWrites(on: [2])

        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(
                    configuration: WebSearchConfiguration(provider: .firecrawl),
                    credential: "new-key"
                )
            )
        }

        #expect((await fixture.coordinator.snapshot()).configuration == before)
        #expect(try fixture.store.load() == before)
        #expect(await fixture.gatewayState.capture().webSearch == before.webSearch)
        #expect(fixture.secrets.value(for: .webSearch(.firecrawl)) == "new-key")
    }

    @Test("A failed credential write is returned without an unnecessary rollback")
    func credentialWriteFailure() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make(
            webSearch: .firecrawlCloud,
            existingCredential: "old-key"
        )
        defer { fixture.removeFiles() }
        let before = try fixture.store.load()
        fixture.secrets.failNextWrite()

        await #expect(throws: ScriptedSecretStore.Error.writeInjected) {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(
                    configuration: WebSearchConfiguration(provider: .firecrawl),
                    credential: "new-key"
                )
            )
        }

        #expect((await fixture.coordinator.snapshot()).configuration == before)
        #expect(try fixture.store.load() == before)
        #expect(fixture.secrets.value(for: .webSearch(.firecrawl)) == "old-key")
    }
}

@MainActor
struct WebSearchCoordinatorFixture {
    let root: URL
    let store: FailNextConfigurationStore
    let secrets: ScriptedSecretStore
    let gatewayState: GatewayState
    let controller: TestClaudeController
    let coordinator: ApplicationCoordinator

    static func make(
        webSearch: WebSearchConfiguration = .disabled,
        existingCredential: String? = nil,
        credentialProvider: WebSearchProvider = .firecrawl
    ) async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-web-search-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "applied")],
            status: .ready
        )
        let initial = AppConfiguration(
            providers: [provider],
            mappings: [
                "claude-opus-5": ModelMapping(
                    providerID: providerID,
                    modelID: "applied"
                )
            ],
            connected: true,
            webSearch: webSearch
        )
        let backing = ConfigurationStore(
            fileURL: root.appending(path: "config.json"),
            backupDirectory: root.appending(path: "configuration-backups")
        )
        try backing.save(initial)
        let store = FailNextConfigurationStore(backing: backing)
        let secrets = ScriptedSecretStore(
            values: existingCredential.map { [.webSearch(credentialProvider): $0] } ?? [:]
        )
        let profile = ClaudeProfileManager(
            paths: ClaudeProfilePaths(applicationSupport: root)
        )
        try profile.activate(autoMode: initial.autoMode, tlsEnabled: false)
        let gatewayState = GatewayState(
            snapshot: RoutingSnapshot(
                generation: 0,
                providers: initial.providers,
                mappings: initial.mappings,
                webSearch: initial.webSearch
            )
        )
        let controller = TestClaudeController()
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: secrets,
            profileManager: profile,
            claudeController: controller,
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            gatewayStateOverride: gatewayState
        )
        _ = try await coordinator.start()
        return Self(
            root: root,
            store: store,
            secrets: secrets,
            gatewayState: gatewayState,
            controller: controller,
            coordinator: coordinator
        )
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}
