import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Claude Desktop catalog failure recovery")
struct ClaudeDesktopCatalogFailureTests {
    @Test("A failed catalog update reopens the old profile without hiding the error", arguments: [false, true])
    func failedUpdate(reopenFails: Bool) async throws {
        let fixture = try await ClaudeDesktopCatalogFailureFixture.make()
        defer { fixture.removeFiles() }
        let before = try Data(contentsOf: fixture.paths.profile)
        fixture.profile.failNextUpdate(FailingDesktopCatalogProfileManager.Error.updateInjected)
        if reopenFails { fixture.controller.failNextOpen() }

        await #expect(throws: FailingDesktopCatalogProfileManager.Error.updateInjected) {
            _ = try await fixture.coordinator.applyClaudeDesktop()
        }

        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.configuration.connected)
        #expect(snapshot.hasPendingClaudeDesktopChanges)
        #expect(snapshot.proxyRunning)
        #expect(try Data(contentsOf: fixture.paths.profile) == before)
        #expect(fixture.controller.quitCount == 1)
        #expect(fixture.controller.openCount == 1)
        #expect(fixture.controller.isRunning() == !reopenFails)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Ownership lost at the update boundary is reported as an external profile change")
    func updateOwnershipFailure() async throws {
        let fixture = try await ClaudeDesktopCatalogFailureFixture.make()
        defer { fixture.removeFiles() }
        let before = try Data(contentsOf: fixture.paths.profile)
        fixture.profile.failNextUpdate(ClaudeProfileManager.Error.inactiveProfile)

        await #expect(throws: ApplicationCoordinator.Error.claudeDesktopProfileChanged) {
            _ = try await fixture.coordinator.applyClaudeDesktop()
        }

        #expect(try Data(contentsOf: fixture.paths.profile) == before)
        #expect((await fixture.coordinator.snapshot()).hasPendingClaudeDesktopChanges)
        #expect(fixture.controller.isRunning())
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Failed compensation cannot mistake the original catalog for the one Desktop loaded")
    func failedCompensationPreservesUnknownCatalog() async throws {
        let fixture = try await ClaudeDesktopCatalogFailureFixture.make()
        defer { fixture.removeFiles() }
        let before = try Data(contentsOf: fixture.paths.profile)
        fixture.profile.failNextUpdate(ClaudeProfileManager.Error.rollbackFailed, afterWriting: true)

        await #expect(throws: ClaudeProfileManager.Error.rollbackFailed) {
            _ = try await fixture.coordinator.applyClaudeDesktop()
        }

        #expect(try Data(contentsOf: fixture.paths.profile) != before)
        #expect(fixture.controller.isRunning())
        let reverted = try await fixture.coordinator.setModelIndicator(.mapsTo)
        #expect(reverted.hasPendingClaudeDesktopChanges)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("An empty routing catalog is not published", arguments: [false, true])
    func invalidRouting(duringQuit: Bool) async throws {
        let fixture = try await ClaudeDesktopCatalogFailureFixture.make()
        defer { fixture.removeFiles() }
        let before = try Data(contentsOf: fixture.paths.profile)
        let removeModels: @MainActor () async throws -> Void = {
            await fixture.discovery.serveCatalog(#"{"data":[{"id":"unmapped"}]}"#)
            _ = try await fixture.coordinator.refreshProvider(id: fixture.providerID)
        }
        if duringQuit { fixture.controller.onQuit = removeModels } else { try await removeModels() }

        await #expect(throws: ApplicationCoordinator.Error.noMappedModel) {
            _ = try await fixture.coordinator.applyClaudeDesktop()
        }

        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.configuration.mappings.isEmpty)
        #expect(snapshot.configuration.connected)
        #expect(snapshot.hasPendingClaudeDesktopChanges)
        #expect(try Data(contentsOf: fixture.paths.profile) == before)
        #expect(fixture.controller.quitCount == (duringQuit ? 1 : 0))
        #expect(fixture.controller.openCount == (duringQuit ? 1 : 0))
        #expect(fixture.controller.isRunning())
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Managed policy prevents catalog changes and subsequent launch", arguments: [false, true])
    func managedPolicy(duringQuit: Bool) async throws {
        let fixture = try await ClaudeDesktopCatalogFailureFixture.make()
        defer { fixture.removeFiles() }
        let before = try Data(contentsOf: fixture.paths.profile)
        if duringQuit {
            fixture.controller.onQuit = { fixture.policy.managed = true }
        } else {
            fixture.policy.managed = true
        }

        await #expect(throws: DesktopApplicationLaunchError.organizationManaged) {
            _ = try await fixture.coordinator.applyClaudeDesktop()
        }

        #expect(try Data(contentsOf: fixture.paths.profile) == before)
        #expect((await fixture.coordinator.snapshot()).hasPendingClaudeDesktopChanges)
        #expect(fixture.controller.quitCount == (duringQuit ? 1 : 0))
        #expect(fixture.controller.openCount == 0)
        #expect(fixture.controller.isRunning() == !duringQuit)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A disconnected profile is never rewritten or reopened by a suspended Apply")
    func disconnectDuringQuit() async throws {
        let fixture = try await ClaudeDesktopCatalogFailureFixture.make()
        defer { fixture.removeFiles() }
        fixture.controller.onQuit = { _ = try await fixture.coordinator.disconnect() }

        await #expect(throws: (any Swift.Error).self) {
            _ = try await fixture.coordinator.applyClaudeDesktop()
        }

        let snapshot = await fixture.coordinator.snapshot()
        #expect(!snapshot.configuration.connected)
        #expect(!snapshot.hasPendingClaudeDesktopChanges)
        #expect(try !fixture.profile.isActive(autoMode: snapshot.configuration.autoMode))
        #expect(fixture.controller.openCount == 0)
        #expect(!fixture.controller.isRunning())
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Handoff shutdown cancels a suspended Apply before profile changes or reopening")
    func handoffDuringQuit() async throws {
        let fixture = try await ClaudeDesktopCatalogFailureFixture.make()
        defer { fixture.removeFiles() }
        let before = try Data(contentsOf: fixture.paths.profile)
        fixture.controller.onQuit = { await fixture.coordinator.shutdown(mode: .handoff) }

        await #expect(throws: CancellationError.self) {
            _ = try await fixture.coordinator.applyClaudeDesktop()
        }

        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.configuration.connected)
        #expect(!snapshot.proxyRunning)
        #expect(snapshot.hasPendingClaudeDesktopChanges)
        #expect(try Data(contentsOf: fixture.paths.profile) == before)
        #expect(fixture.controller.openCount == 0)
        #expect(!fixture.controller.isRunning())
    }

    @Test("An Apply entering after shutdown cannot change the profile or control Desktop")
    func applyAfterShutdown() async throws {
        let fixture = try await ClaudeDesktopCatalogFailureFixture.make()
        defer { fixture.removeFiles() }
        let before = try Data(contentsOf: fixture.paths.profile)
        await fixture.coordinator.shutdown(mode: .handoff)

        await #expect(throws: CancellationError.self) {
            _ = try await fixture.coordinator.applyClaudeDesktop()
        }

        let snapshot = await fixture.coordinator.snapshot()
        #expect(!snapshot.proxyRunning)
        #expect(snapshot.hasPendingClaudeDesktopChanges)
        #expect(try Data(contentsOf: fixture.paths.profile) == before)
        #expect(fixture.controller.quitCount == 0)
        #expect(fixture.controller.openCount == 0)
        #expect(fixture.controller.isRunning())
    }

    @Test("A second Apply cannot control Desktop while the first is reopening it")
    func duplicateApply() async throws {
        let fixture = try await ClaudeDesktopCatalogFailureFixture.make()
        defer { fixture.removeFiles() }
        fixture.controller.onOpen = {
            fixture.controller.onOpen = nil
            await #expect(throws: CancellationError.self) {
                _ = try await fixture.coordinator.applyClaudeDesktop()
            }
        }

        let snapshot = try await fixture.coordinator.applyClaudeDesktop()

        #expect(!snapshot.hasPendingClaudeDesktopChanges)
        #expect(fixture.controller.quitCount == 1)
        #expect(fixture.controller.openCount == 1)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Failed startup disconnection persistence keeps the saved restoration responsibility")
    func startupSaveFailure() async throws {
        let store = ScriptedConfigurationStore(configuration: AppConfiguration(connected: true))
        store.failSaves(on: [1])
        let profile = ScriptedClaudeProfileManager(active: true)
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: profile,
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer())

        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await coordinator.start()
        }

        #expect(store.configuration.connected)
        #expect((await coordinator.snapshot()).configuration.connected)
        #expect(profile.restoreCount == 1)
        #expect(try !profile.isActive(autoMode: true))
        await coordinator.shutdown(mode: .handoff)
    }
}
