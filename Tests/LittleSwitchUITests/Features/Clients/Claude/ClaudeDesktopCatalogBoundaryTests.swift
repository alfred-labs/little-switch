import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Claude Desktop catalog action boundaries")
struct ClaudeDesktopCatalogBoundaryTests {
    @Test("An unchanged or disconnected catalog does not control the application", arguments: [false, true])
    func noOp(connected: Bool) async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(connected: connected, claudeRunning: true)
        defer { fixture.removeFiles() }

        let result = try await fixture.coordinator.applyClaudeDesktop()

        #expect(!result.hasPendingClaudeDesktopChanges)
        #expect(result.configuration.connected == connected)
        #expect(fixture.controller.quitCount == 0)
        #expect(fixture.controller.openCount == 0)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Catalog Apply never commits an unconfirmed mapping draft")
    func uncommittedMapping() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(claudeRunning: true)
        defer { fixture.removeFiles() }
        _ = try await fixture.coordinator.setMapping(
            routeID: "claude-sonnet-5", mapping: ModelMapping(providerID: fixture.providerID, modelID: "applied"))

        let result = try await fixture.coordinator.applyClaudeDesktop()

        #expect(result.hasPendingClaudeDesktopChanges)
        #expect(result.hasPendingClaudeMappings)
        #expect(try fixture.store.load().mappings["claude-sonnet-5"] == nil)
        #expect(fixture.controller.quitCount == 0)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Foreign profile changes are not overwritten or restarted")
    func foreignProfile() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(claudeRunning: true)
        defer { fixture.removeFiles() }
        _ = try await fixture.coordinator.setModelIndicator(.none)
        let paths = ClaudeProfilePaths(applicationSupport: fixture.root)
        let store = DiskClaudeProfileFileStore(backupDirectory: paths.backupDirectory)
        var profile = try store.readObject(paths.profile)
        profile["inferenceGatewayBaseUrl"] = "https://foreign.example.invalid"
        try store.writeObject(profile, to: paths.profile)
        let before = try Data(contentsOf: paths.profile)

        await #expect(throws: ApplicationCoordinator.Error.claudeDesktopProfileChanged) {
            _ = try await fixture.coordinator.applyClaudeDesktop()
        }

        #expect(try Data(contentsOf: paths.profile) == before)
        #expect(fixture.controller.quitCount == 0)
        #expect(fixture.controller.openCount == 0)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Changes during quit are included; changes during reopening remain pending", arguments: [false, true])
    func reentrantCatalogChange(duringOpen: Bool) async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(claudeRunning: true)
        defer {
            fixture.controller.onQuit = nil
            fixture.controller.onOpen = nil
            fixture.removeFiles()
        }
        _ = try await fixture.coordinator.setModelIndicator(.none)
        let change: @MainActor () async throws -> Void = {
            _ = try await fixture.coordinator.setModelIndicator(.swap)
        }
        if duringOpen { fixture.controller.onOpen = change } else { fixture.controller.onQuit = change }

        let result = try await fixture.coordinator.applyClaudeDesktop()

        #expect(result.configuration.modelIndicator == .swap)
        #expect(result.hasPendingClaudeDesktopChanges == duringOpen)
        let written = ClaudeCodeModelChoice.available(
            providers: result.configuration.providers,
            mappings: result.configuration.mappings,
            indicator: duringOpen ? .none : .swap)
        let profile = ClaudeProfileManager(paths: ClaudeProfilePaths(applicationSupport: fixture.root))
        #expect(try profile.catalogMatches(written))
        #expect(fixture.controller.quitCount == 1)
        #expect(fixture.controller.openCount == 1)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
