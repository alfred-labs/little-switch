import Foundation
import LittleSwitchCommon
import LittleSwitchCore

@testable import LittleSwitchUI

@MainActor
struct ClaudeDesktopCatalogFailureFixture {
    let root: URL
    let paths: ClaudeProfilePaths
    let providerID: UUID
    let profile: FailingDesktopCatalogProfileManager
    let controller: TestClaudeController
    let policy: DesktopCatalogTestPolicy
    let discovery: StaticCatalogTransport
    let coordinator: ApplicationCoordinator

    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-catalog-failures-\(UUID().uuidString)", directoryHint: .isDirectory)
        let paths = ClaudeProfilePaths(applicationSupport: root)
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "applied")],
            status: .ready)
        let configuration = AppConfiguration(
            providers: [provider],
            mappings: ["claude-opus-5": ModelMapping(providerID: provider.id, modelID: "applied")],
            connected: true)
        let store = ConfigurationStore(
            fileURL: paths.littleSwitchConfig, backupDirectory: root.appending(path: "configuration-backups"))
        try store.save(configuration)
        let profile = FailingDesktopCatalogProfileManager(backing: ClaudeProfileManager(paths: paths))
        try profile.activate(autoMode: configuration.autoMode, tlsEnabled: false)
        let controller = TestClaudeController(running: true)
        let policy = DesktopCatalogTestPolicy()
        let manager = DesktopApplicationManager(
            locateApplication: { _ in URL(filePath: "/Applications/Test.app") },
            isClaudeOrganizationManaged: { policy.managed },
            openApplication: { _ in })
        let discovery = StaticCatalogTransport()
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: profile,
            claudeController: controller,
            desktopApplications: manager,
            discoveryTransport: discovery,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer())
        _ = try await coordinator.start()
        _ = try await coordinator.setModelIndicator(.none)
        return Self(
            root: root,
            paths: paths,
            providerID: provider.id,
            profile: profile,
            controller: controller,
            policy: policy,
            discovery: discovery,
            coordinator: coordinator)
    }

    func removeFiles() {
        controller.onQuit = nil
        controller.onOpen = nil
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
final class DesktopCatalogTestPolicy {
    var managed = false
}

/// Keep real profile persistence and ownership checks; inject only a failure
/// returned at the catalog-update boundary after the coordinator has quit Desktop.
final class FailingDesktopCatalogProfileManager: ClaudeProfileManaging, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case updateInjected
    }

    private struct UpdateFailure {
        let error: any Swift.Error
        let afterWriting: Bool
    }

    private let lock = NSLock()
    private let backing: ClaudeProfileManager
    private var updateFailure: UpdateFailure?

    init(backing: ClaudeProfileManager) {
        self.backing = backing
    }

    func failNextUpdate(_ error: any Swift.Error, afterWriting: Bool = false) {
        lock.withLock { updateFailure = UpdateFailure(error: error, afterWriting: afterWriting) }
    }

    func activate(autoMode: Bool, tlsEnabled: Bool) throws {
        try backing.activate(autoMode: autoMode, tlsEnabled: tlsEnabled)
    }

    func restore() throws {
        try backing.restore()
    }

    func isActive(autoMode: Bool) throws -> Bool {
        try backing.isActive(autoMode: autoMode)
    }

    func catalogMatches(_ choices: [ClaudeCodeModelChoice]) throws -> Bool {
        try backing.catalogMatches(choices)
    }

    func updateCatalog(_ choices: [ClaudeCodeModelChoice], autoMode: Bool) throws {
        let failure = lock.withLock {
            defer { updateFailure = nil }
            return updateFailure
        }
        if let failure {
            if failure.afterWriting { try backing.updateCatalog(choices, autoMode: autoMode) }
            throw failure.error
        }
        try backing.updateCatalog(choices, autoMode: autoMode)
    }
}
