import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator Claude lifecycle coverage")
struct CoordinatorLifecycleCoverageTests {
    @Test("Connect validates routing and relaunches a running Claude")
    func connectValidation() async throws {
        let invalid = try await LifecycleCoverageFixture.make(validRouting: false)
        await #expect(throws: ApplicationCoordinator.Error.noMappedModel) {
            _ = try await invalid.coordinator.connect()
        }
        #expect(!(await invalid.coordinator.snapshot()).configuration.connected)
        await invalid.coordinator.shutdown(mode: .handoff)

        let running = try await LifecycleCoverageFixture.make(claudeRunning: true)
        let connected = try await running.coordinator.connect()
        #expect(connected.configuration.connected)
        #expect(running.controller.quitAttempts == 1)
        #expect(running.controller.openAttempts == 1)
        #expect(running.profile.activationCount == 1)
        await running.coordinator.shutdown(mode: .handoff)
    }

    @Test("A stopped Claude connects without process control")
    func connectWhileStopped() async throws {
        let fixture = try await LifecycleCoverageFixture.make()

        let connected = try await fixture.coordinator.connect()

        #expect(connected.configuration.connected)
        #expect(fixture.controller.quitAttempts == 0)
        #expect(fixture.controller.openAttempts == 0)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Connect rolls back activation and save failures", arguments: ConnectFailure.allCases)
    func connectFailureRollback(failure: ConnectFailure) async throws {
        let fixture = try await LifecycleCoverageFixture.make()
        switch failure {
        case .activation:
            fixture.profile.failActivations(on: [1])
            await #expect(throws: ScriptedClaudeProfileManager.Error.activateInjected) {
                _ = try await fixture.coordinator.connect()
            }
        case .save:
            fixture.store.failFutureSaves(at: [1])
            await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
                _ = try await fixture.coordinator.connect()
            }
        }

        #expect(!(await fixture.coordinator.snapshot()).configuration.connected)
        #expect(fixture.controller.quitAttempts == 0)
        #expect(fixture.controller.openAttempts == 0)
        #expect(fixture.profile.restoreCount == 1)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Connect preserves the original error when every best-effort rollback fails")
    func connectRollbackFailures() async throws {
        let fixture = try await LifecycleCoverageFixture.make()
        fixture.store.failFutureSaves(at: [1, 2])
        fixture.profile.failRestores(on: [1])

        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.connect()
        }

        #expect(fixture.controller.quitAttempts == 0)
        #expect(fixture.controller.openAttempts == 0)
        #expect(fixture.profile.restoreCount == 1)
        #expect(!(await fixture.coordinator.snapshot()).configuration.connected)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Disconnect covers success, restore failure, and save failure")
    func disconnectBranches() async throws {
        let running = try await LifecycleCoverageFixture.make(
            connected: true,
            claudeRunning: true
        )
        let disconnected = try await running.coordinator.disconnect()
        #expect(!disconnected.configuration.connected)
        #expect(running.controller.quitAttempts == 1)
        #expect(running.controller.openAttempts == 1)
        await running.coordinator.shutdown(mode: .handoff)

        let restoreFailure = try await LifecycleCoverageFixture.make(connected: true)
        restoreFailure.profile.failRestores(on: [1])
        await #expect(throws: ScriptedClaudeProfileManager.Error.restoreInjected) {
            _ = try await restoreFailure.coordinator.disconnect()
        }
        #expect((await restoreFailure.coordinator.snapshot()).configuration.connected)
        await restoreFailure.coordinator.shutdown(mode: .handoff)

        let saveFailure = try await LifecycleCoverageFixture.make(connected: true)
        saveFailure.store.failFutureSaves(at: [1])
        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await saveFailure.coordinator.disconnect()
        }
        #expect(!(await saveFailure.coordinator.snapshot()).configuration.connected)
        await saveFailure.coordinator.shutdown(mode: .handoff)
    }

    @Test("Applying an all-unassigned mapping draft is refused while Desktop is connected")
    func liveUnmapLastRouteRefused() async throws {
        let fixture = try await LifecycleCoverageFixture.make(connected: true)

        let drafted = try await fixture.coordinator.setMapping(
            routeID: "claude-sonnet-5",
            mapping: nil
        )
        #expect(drafted.hasPendingClaudeMappings)

        await #expect(throws: ApplicationCoordinator.Error.noMappedModel) {
            _ = try await fixture.coordinator.applyClaudeMappings()
        }

        #expect(!fixture.store.configuration.mappings.isEmpty)
        #expect(fixture.profile.activationCount == 0)
        #expect(fixture.controller.quitAttempts == 0)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Live auto mode rewrites the profile without controlling a stopped client")
    func liveAutoModeWithoutProcessControl() async throws {
        let fixture = try await LifecycleCoverageFixture.make(connected: true)

        let changed = try await fixture.coordinator.setAutoMode(false)

        #expect(!changed.configuration.autoMode)
        #expect(fixture.profile.activationCount == 1)
        #expect(fixture.controller.quitAttempts == 0)
        #expect(fixture.controller.openAttempts == 0)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}

enum ConnectFailure: CaseIterable, Sendable {
    case activation
    case save
}

@MainActor
private struct LifecycleCoverageFixture {
    let store: ScriptedConfigurationStore
    let profile: ScriptedClaudeProfileManager
    let controller: ScriptedApplicationController
    let transport: ScriptedCatalogTransport
    let coordinator: ApplicationCoordinator

    static func make(
        validRouting: Bool = true,
        connected: Bool = false,
        claudeRunning: Bool = false
    ) async throws -> Self {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "applied"), DiscoveredModel(id: "replacement")],
            status: .ready
        )
        let mapping = ModelMapping(providerID: providerID, modelID: "applied")
        let configuration = AppConfiguration(
            providers: [provider],
            mappings: validRouting ? ["claude-sonnet-5": mapping] : [:],
            connected: connected
        )
        let store = ScriptedConfigurationStore(configuration: configuration)
        let profile = ScriptedClaudeProfileManager(active: connected)
        let controller = ScriptedApplicationController(running: claudeRunning)
        let transport = ScriptedCatalogTransport()
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: profile,
            claudeController: controller,
            discoveryTransport: transport,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
        _ = try await coordinator.start()
        return Self(
            store: store,
            profile: profile,
            controller: controller,
            transport: transport,
            coordinator: coordinator
        )
    }
}
