import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator transaction")
struct ApplicationCoordinatorTransactionTests {
    @Test("Connected remaps wait for apply; auto mode relaunches live")
    func connectedRemapsWaitForApply() async throws {
        let fixture = try await TransactionalCoordinatorFixture.make()
        defer { fixture.removeFiles() }
        let replacement = ModelMapping(
            providerID: fixture.providerID,
            modelID: "replacement"
        )

        let drafted = try await fixture.coordinator.setMapping(
            routeID: "claude-opus-5",
            mapping: replacement
        )
        // The draft waits: nothing persisted, nothing hot-swapped.
        #expect(drafted.hasPendingClaudeMappings)
        #expect(
            try fixture.store.load().mappings["claude-opus-5"]
                == fixture.appliedConfiguration.mappings["claude-opus-5"]
        )
        #expect(
            await fixture.gatewayState.capture().mappings["claude-opus-5"]
                == fixture.appliedConfiguration.mappings["claude-opus-5"]
        )

        let applied = try await fixture.coordinator.applyClaudeMappings()
        let autoChanged = try await fixture.coordinator.setAutoMode(false)

        #expect(!applied.hasPendingClaudeMappings)
        #expect(applied.configuration.mappings["claude-opus-5"] == replacement)
        #expect(
            try fixture.store.load().mappings["claude-opus-5"] == replacement
        )
        #expect(
            await fixture.gatewayState.capture().mappings["claude-opus-5"]
                == replacement
        )
        #expect(!autoChanged.configuration.autoMode)
        #expect(try fixture.store.load().autoMode == false)
        #expect(fixture.profile.appliedAutoMode == false)
        // A remap is routing-only; auto mode is the sole relaunch-worthy change.
        #expect(fixture.controller.quitCount == 1)
        #expect(fixture.controller.openCount == 1)
    }

    @Test(
        "Live auto mode rollback restores every layer",
        arguments: AutoModeFailurePoint.allCases
    )
    func liveAutoModeRollsBackEveryLayer(failure: AutoModeFailurePoint) async throws {
        let fixture = try await TransactionalCoordinatorFixture.make()
        defer { fixture.removeFiles() }
        fixture.arm(failure)

        await #expect(throws: (any Swift.Error).self) {
            _ = try await fixture.coordinator.setAutoMode(false)
        }

        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.configuration.autoMode == fixture.appliedConfiguration.autoMode)
        if failure != .rollbackSave {
            #expect(try fixture.store.load() == fixture.appliedConfiguration)
        }
        #expect(fixture.profile.appliedAutoMode == fixture.appliedConfiguration.autoMode)
        #expect(fixture.controller.isRunning())
        #expect(fixture.controller.quitCount == 0)
    }

    @Test("A failed Desktop relaunch reports the error after committing")
    func relaunchFailureReportsAfterCommit() async throws {
        let fixture = try await TransactionalCoordinatorFixture.make()
        defer { fixture.removeFiles() }
        fixture.controller.failNextQuit()

        await #expect(throws: ApplicationCoordinator.Error.relaunchFailed) {
            _ = try await fixture.coordinator.setAutoMode(false)
        }

        // Configuration and profile are committed; only the relaunch failed.
        #expect(try fixture.store.load().autoMode == false)
        #expect(fixture.profile.appliedAutoMode == false)
        #expect(fixture.controller.quitCount == 0)
        #expect(fixture.controller.openCount == 0)
    }

    @Test("Disconnect keeps live-persisted settings and restores the profile")
    func disconnectKeepsLiveSettings() async throws {
        let fixture = try await TransactionalCoordinatorFixture.make()
        defer { fixture.removeFiles() }
        _ = try await fixture.coordinator.setAutoMode(false)

        let disconnected = try await fixture.coordinator.disconnect()

        #expect(!disconnected.configuration.connected)
        #expect(!disconnected.configuration.autoMode)
        #expect(!(try fixture.store.load()).autoMode)
    }

    @Test("Shutdown keeps live-persisted settings on disk")
    func shutdownKeepsLiveSettings() async throws {
        let fixture = try await TransactionalCoordinatorFixture.make()
        defer { fixture.removeFiles() }
        _ = try await fixture.coordinator.setAutoMode(false)

        await fixture.coordinator.shutdown()

        let stopped = await fixture.coordinator.snapshot()
        #expect(!stopped.configuration.connected)
        #expect(!(try fixture.store.load()).autoMode)
    }
}

enum AutoModeFailurePoint: CaseIterable, Sendable {
    case profileActivation
    case configurationSave
    case rollbackSave
}

private final class ControlledProfileManager: ClaudeProfileManaging, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case activationInjected
    }

    private let lock = NSLock()
    private var autoMode: Bool?
    private var shouldFailNextActivation = false

    init(autoMode: Bool?) {
        self.autoMode = autoMode
    }

    var appliedAutoMode: Bool? {
        lock.withLock { autoMode }
    }

    func activate(autoMode: Bool, tlsEnabled: Bool) throws {
        try lock.withLock {
            if shouldFailNextActivation {
                shouldFailNextActivation = false
                throw Error.activationInjected
            }
            self.autoMode = autoMode
        }
    }

    func restore() throws {
        lock.withLock {
            autoMode = nil
        }
    }

    func isActive(autoMode: Bool) throws -> Bool {
        lock.withLock { self.autoMode == autoMode }
    }

    func failNextActivation() {
        lock.withLock {
            shouldFailNextActivation = true
        }
    }
}

@MainActor
private struct TransactionalCoordinatorFixture {
    let root: URL
    let providerID: UUID
    let store: FailNextConfigurationStore
    let appliedConfiguration: AppConfiguration
    let gatewayState: GatewayState
    let profile: ControlledProfileManager
    let controller: TestClaudeController
    let coordinator: ApplicationCoordinator

    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-transaction-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [
                DiscoveredModel(id: "applied"),
                DiscoveredModel(id: "replacement"),
            ],
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
            autoMode: true,
            connected: true
        )
        let backing = ConfigurationStore(
            fileURL: root.appending(path: "config.json"),
            backupDirectory: root.appending(path: "configuration-backups")
        )
        try backing.save(initial)
        let store = FailNextConfigurationStore(backing: backing)
        let gatewayState = GatewayState(
            snapshot: RoutingSnapshot(
                generation: 0,
                providers: initial.providers,
                mappings: initial.mappings
            )
        )
        let profile = ControlledProfileManager(autoMode: initial.autoMode)
        let controller = TestClaudeController(running: true)
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
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
            providerID: providerID,
            store: store,
            appliedConfiguration: try store.load(),
            gatewayState: gatewayState,
            profile: profile,
            controller: controller,
            coordinator: coordinator
        )
    }

    func arm(_ failure: AutoModeFailurePoint) {
        switch failure {
        case .profileActivation:
            profile.failNextActivation()
        case .configurationSave:
            store.failNextSave()
        case .rollbackSave:
            profile.failNextActivation()
            store.failSaves(skipping: 1)
        }
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}
