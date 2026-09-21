import Foundation
import LittleSwitchCommon
import LittleSwitchCore

@testable import LittleSwitchUI

@MainActor
struct ConnectedCoordinatorFixture {
    let root: URL
    let providerID: UUID
    let store: any ConfigurationStoring
    /// Set when the fixture was built with `injectFailingStore`, so tests
    /// can arm save failures against the wrapped store.
    let failingStore: FailNextConfigurationStore?
    let secrets: MemorySecretStore
    let appliedConfiguration: AppConfiguration
    let gatewayState: GatewayState
    let controller: TestClaudeController
    let discoveryTransport: StaticCatalogTransport
    let coordinator: ApplicationCoordinator

    static func make(
        connected: Bool = true,
        discoveryTransport: StaticCatalogTransport = StaticCatalogTransport(),
        tlsProvisioner: (any GatewayTLSProvisioning)? = nil,
        injectFailingStore: Bool = false,
        claudeCodeConnected: Bool = false,
        mapsSecondRoute: Bool = false,
        models: [DiscoveredModel] = [DiscoveredModel(id: "applied"), DiscoveredModel(id: "replacement")]
    ) async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-connected-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: models,
            status: .ready
        )
        var initial = AppConfiguration(
            providers: [provider],
            mappings: [
                "claude-opus-5": ModelMapping(
                    providerID: providerID,
                    modelID: "applied"
                )
            ],
            autoMode: true,
            connected: connected
        )
        if mapsSecondRoute {
            initial.mappings["claude-sonnet-5"] = ModelMapping(
                providerID: providerID,
                modelID: "applied"
            )
        }
        if claudeCodeConnected {
            initial.claudeCode.connected = true
        }
        let store = ConfigurationStore(
            fileURL: root.appending(path: "config.json"),
            backupDirectory: root.appending(path: "configuration-backups")
        )
        try store.save(initial)
        let failingStore =
            injectFailingStore
            ? FailNextConfigurationStore(backing: store)
            : nil
        let wrappedStore: any ConfigurationStoring = failingStore ?? store
        let profile = ClaudeProfileManager(
            paths: ClaudeProfilePaths(applicationSupport: root)
        )
        if connected {
            try profile.activate(autoMode: initial.autoMode, tlsEnabled: false)
        }
        let gatewayState = GatewayState(
            snapshot: RoutingSnapshot(
                generation: 0,
                providers: initial.providers,
                mappings: initial.mappings,
                codex: initial.codex,
                webSearch: initial.webSearch,
                modelIndicator: initial.modelIndicator
            )
        )
        let controller = TestClaudeController()
        let secrets = MemorySecretStore()
        let coordinator = ApplicationCoordinator(
            configurationStore: wrappedStore,
            secretStore: secrets,
            profileManager: profile,
            claudeController: controller,
            claudeCodeProfileManager: claudeCodeConnected
                ? TestClaudeCodeProfileManager(status: .active)
                : nil,
            discoveryTransport: discoveryTransport,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            gatewayStateOverride: gatewayState,
            tlsProvisioner: tlsProvisioner
        )
        _ = try await coordinator.start()
        return Self(
            root: root,
            providerID: providerID,
            store: wrappedStore,
            failingStore: failingStore,
            secrets: secrets,
            appliedConfiguration: try store.load(),
            gatewayState: gatewayState,
            controller: controller,
            discoveryTransport: discoveryTransport,
            coordinator: coordinator
        )
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}
