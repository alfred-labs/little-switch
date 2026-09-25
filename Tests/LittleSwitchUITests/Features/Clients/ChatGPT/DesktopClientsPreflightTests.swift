import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Shared desktop connection preflight")
struct DesktopClientsPreflightTests {
    @Test("Missing desktop control leaves the saved connection intact", arguments: [false, true])
    func unavailableDesktop(disconnect: Bool) async throws {
        let fixture = try await ChatGPTFixture.make(connected: disconnect, hasController: false)
        let previous = fixture.store.configuration
        let previousEvents = fixture.events.recorded
        await #expect(throws: ChatGPTConnectionError.unavailable) {
            if disconnect { return try await fixture.coordinator.disconnectDesktopClients() }
            return try await fixture.coordinator.connectDesktopClients()
        }
        #expect(fixture.store.configuration == previous)
        #expect(fixture.events.recorded == previousEvents)
        #expect(fixture.codexProfile.activations.isEmpty)
        #expect(await fixture.server.isRunning == disconnect)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A Chat choice does not implicitly expose a model to Codex")
    func emptyCodexExposure() async throws {
        let fixture = try await ChatGPTFixture.make(hasCodexExposure: false)
        let previous = fixture.store.configuration
        await #expect(throws: ApplicationCoordinator.Error.noExposedCodexModel) {
            try await fixture.coordinator.connectDesktopClients()
        }
        #expect(fixture.store.configuration == previous)
        #expect(fixture.events.recorded.isEmpty)
        #expect(fixture.codexProfile.activations.isEmpty)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("An existing custom backend is preserved without quitting the desktop")
    func conflictingEnvironment() async throws {
        let fixture = try await ChatGPTFixture.make(
            environment: ["CODEX_API_BASE_URL": "https://example.test/backend-api"])
        let previous = fixture.store.configuration
        await #expect(throws: ChatGPTConnectionError.conflictingEnvironment) {
            try await fixture.coordinator.connectDesktopClients()
        }
        #expect(fixture.store.configuration == previous)
        #expect(fixture.events.recorded.isEmpty)
        #expect(fixture.codexProfile.activations.isEmpty)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A refused rollback quit leaves profile restoration available for retry")
    func refusedRollbackQuit() async throws {
        let fixture = try await ChatGPTFixture.make()
        let previous = fixture.store.configuration
        fixture.controller.onOpen = { _ in fixture.controller.failQuit = true }
        fixture.store.failNextSave()
        await #expect(throws: ChatGPTConnectionError.rollbackFailed) {
            try await fixture.coordinator.connectDesktopClients()
        }
        #expect(fixture.store.configuration == previous)
        #expect(fixture.codexProfile.restoreCount == 0)
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .needsAttention)
        #expect(fixture.controller.running)
        fixture.controller.onOpen = nil
        fixture.controller.failQuit = false
        _ = try await fixture.coordinator.disconnectDesktopClients()
        #expect(try !fixture.codexProfile.isActive(providers: previous.providers, configuration: previous.codex))
        #expect(fixture.store.configuration == previous)
        #expect(fixture.controller.running)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
