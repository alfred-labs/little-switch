import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Shared desktop handoff recovery")
struct DesktopClientsHandoffTests {
    @Test("Handoff retains unresolved profile restoration until Disconnect recovers")
    func failedRollbackBlocksHandoff() async throws {
        let fixture = try await ChatGPTFixture.make()
        fixture.store.failNextSave()
        fixture.codexProfile.failNextRestore()
        await #expect(throws: ChatGPTConnectionError.rollbackFailed) {
            try await fixture.coordinator.connectDesktopClients()
        }
        #expect(await !fixture.coordinator.shutdown(mode: .handoff))
        #expect(await !fixture.coordinator.isShuttingDown)
        #expect(await fixture.coordinator.desktopProfileRestorationRequired)
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .needsAttention)
        _ = try await fixture.coordinator.disconnectDesktopClients()
        #expect(await !fixture.coordinator.desktopProfileRestorationRequired)
        let configuration = fixture.store.configuration
        #expect(
            try !fixture.codexProfile.isActive(providers: configuration.providers, configuration: configuration.codex))
        #expect(fixture.controller.running)
        #expect(await fixture.coordinator.shutdown(mode: .handoff))
    }

    @Test("Handoff checks restoration responsibility after the cancelled connection settles")
    func rollbackFailureDuringHandoffKeepsListener() async throws {
        let fixture = try await ChatGPTFixture.make()
        let entered = AsyncTestGate()
        let release = AsyncTestGate()
        fixture.controller.onOpen = { _ in
            await entered.open()
            try? await release.wait()
        }
        fixture.codexProfile.failNextRestore()
        let operation = Task { try await fixture.coordinator.connectDesktopClients() }
        try await entered.wait(description: "managed desktop launch before handoff")
        #expect(await !fixture.coordinator.shutdown(mode: .handoff))
        await #expect(throws: ChatGPTConnectionError.rollbackFailed) { try await operation.value }
        #expect(await !fixture.coordinator.isShuttingDown)
        #expect(await fixture.coordinator.desktopProfileRestorationRequired)
        #expect(await fixture.server.isRunning)
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .needsAttention)
        await release.open()
        fixture.controller.onOpen = nil
        _ = try await fixture.coordinator.disconnectDesktopClients()
        #expect(await !fixture.coordinator.desktopProfileRestorationRequired)
        #expect(await fixture.coordinator.shutdown(mode: .handoff))
    }
}
