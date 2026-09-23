import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Claude Desktop catalog coordination")
struct ClaudeDesktopCatalogCoordinatorTests {
    @Test("A discovery capacity change waits for explicit Apply without restarting Claude", arguments: [false, true])
    func refreshedCatalogWaitsForApply(running: Bool) async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(claudeRunning: running)
        defer { fixture.removeFiles() }
        let paths = ClaudeProfilePaths(applicationSupport: fixture.root)
        let profile = ClaudeProfileManager(paths: paths)
        let before = try Data(contentsOf: paths.profile)
        #expect(!(await fixture.coordinator.snapshot()).hasPendingClaudeDesktopChanges)
        await fixture.discoveryTransport.serveCatalog(
            #"{"data":[{"id":"applied","context_length":1048576},{"id":"replacement"}]}"#)

        let refreshed = try await fixture.coordinator.refreshProvider(id: fixture.providerID)

        #expect(refreshed.configuration.connected)
        #expect(refreshed.hasPendingClaudeDesktopChanges)
        #expect(fixture.controller.quitCount == 0)
        #expect(fixture.controller.openCount == 0)
        #expect(try Data(contentsOf: paths.profile) == before)
        let desired = ClaudeCodeModelChoice.available(
            providers: refreshed.configuration.providers, mappings: refreshed.configuration.mappings)
        #expect(try !profile.catalogMatches(desired))
        let routing = await fixture.gatewayState.capture()
        #expect(routing.providers.first?.models.first?.supports1MContext == true)

        let applied = try await fixture.coordinator.applyClaudeDesktop()

        #expect(!applied.hasPendingClaudeDesktopChanges)
        #expect(try profile.catalogMatches(desired))
        #expect(fixture.controller.quitCount == (running ? 1 : 0))
        #expect(fixture.controller.openCount == (running ? 1 : 0))
        #expect(fixture.controller.isRunning() == running)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Catalog changes in a mapping draft require Desktop Apply, ordinary remaps do not")
    func mappingCatalogBoundary() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(claudeRunning: true)
        defer { fixture.removeFiles() }
        let replacement = ModelMapping(providerID: fixture.providerID, modelID: "replacement")

        let remap = try await fixture.coordinator.setMapping(routeID: "claude-opus-5", mapping: replacement)
        #expect(remap.hasPendingClaudeMappings)
        #expect(!remap.hasPendingClaudeDesktopChanges)
        let hotApplied = try await fixture.coordinator.applyClaudeMappings()
        #expect(!hotApplied.hasPendingClaudeDesktopChanges)
        #expect(fixture.controller.quitCount == 0)

        let newRoute = try await fixture.coordinator.setMapping(routeID: "claude-sonnet-5", mapping: replacement)
        #expect(newRoute.hasPendingClaudeDesktopChanges)
        let saved = try await fixture.coordinator.applyClaudeMappings()
        #expect(saved.hasPendingClaudeDesktopChanges)
        #expect(fixture.controller.quitCount == 0)
        let applied = try await fixture.coordinator.applyClaudeDesktop()
        #expect(!applied.hasPendingClaudeDesktopChanges)
        #expect(fixture.controller.quitCount == 1)
        #expect(fixture.controller.openCount == 1)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("An indicator change is pending until applied and reverting it clears the difference")
    func indicatorDifference() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(claudeRunning: true)
        defer { fixture.removeFiles() }
        let changed = try await fixture.coordinator.setModelIndicator(.none)
        #expect(changed.hasPendingClaudeDesktopChanges)
        let reverted = try await fixture.coordinator.setModelIndicator(.mapsTo)
        #expect(!reverted.hasPendingClaudeDesktopChanges)
        #expect(fixture.controller.quitCount == 0)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Refused quit keeps the old profile and the pending action")
    func quitFailurePreservesCatalog() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(claudeRunning: true)
        defer { fixture.removeFiles() }
        _ = try await fixture.coordinator.setModelIndicator(.none)
        let path = ClaudeProfilePaths(applicationSupport: fixture.root).profile
        let before = try Data(contentsOf: path)
        fixture.controller.failNextQuit()

        await #expect(throws: TestClaudeController.Error.quitInjected) {
            _ = try await fixture.coordinator.applyClaudeDesktop()
        }

        #expect(try Data(contentsOf: path) == before)
        #expect((await fixture.coordinator.snapshot()).hasPendingClaudeDesktopChanges)
        #expect(fixture.controller.isRunning())
        #expect(fixture.controller.openCount == 0)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Failed reopening keeps Apply available for a safe retry")
    func openFailurePreservesPending() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(claudeRunning: true)
        defer { fixture.removeFiles() }
        _ = try await fixture.coordinator.setModelIndicator(.none)
        fixture.controller.failNextOpen()

        await #expect(throws: TestClaudeController.Error.openInjected) {
            _ = try await fixture.coordinator.applyClaudeDesktop()
        }

        #expect((await fixture.coordinator.snapshot()).hasPendingClaudeDesktopChanges)
        #expect(!fixture.controller.isRunning())
        let applied = try await fixture.coordinator.applyClaudeDesktop()
        #expect(!applied.hasPendingClaudeDesktopChanges)
        #expect(!fixture.controller.isRunning())
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
