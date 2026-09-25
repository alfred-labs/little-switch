import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("ChatGPT startup recovery restoration")
struct ChatGPTRecoveryRestorationTests {
    @Test(
        "Recovery intent cannot roll a failed disconnect back to managed routing",
        arguments: ["trust", "listener", "ready"],
        ["save", "open"]
    )
    func failedRecoveryDisconnect(recoveryFailure: String, disconnectFailure: String) async throws {
        let fixture = try await ChatGPTFixture.make(
            connected: true,
            trusted: recoveryFailure != "trust",
            failListenerStart: recoveryFailure == "listener"
        )
        let recovered = recoveryFailure == "ready"
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == (recovered ? .ready : .needsAttention))
        #expect(await fixture.server.isRunning == recovered)
        if disconnectFailure == "save" { fixture.store.failNextSave() }
        if disconnectFailure == "open" { fixture.controller.failOpen = true }

        await #expect(throws: (any Error).self) { try await fixture.coordinator.disconnectDesktopClients() }

        #expect(fixture.controller.running)
        #expect(!fixture.controller.environments.isEmpty)
        #expect(fixture.controller.environments.allSatisfy { $0["CODEX_API_BASE_URL"] == nil })
        #expect(fixture.store.configuration.chatgpt.connected)
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .needsAttention)
        #expect(await fixture.mainServer.isRunning)
        #expect(await fixture.server.isRunning == recovered)
        _ = try await fixture.coordinator.disconnectDesktopClients()
        #expect(!fixture.store.configuration.chatgpt.connected)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A previously managed desktop falls back to normal routing after its listener stops")
    func lostListenerDisconnectRollback() async throws {
        let fixture = try await ChatGPTFixture.make()
        _ = try await fixture.coordinator.connectChatGPT()
        await fixture.server.stop()
        let environmentCount = fixture.controller.environments.count
        fixture.store.failNextSave()
        await #expect(throws: (any Error).self) { try await fixture.coordinator.disconnectDesktopClients() }
        #expect(fixture.controller.running)
        #expect(
            fixture.controller.environments.dropFirst(environmentCount).allSatisfy { $0["CODEX_API_BASE_URL"] == nil }
        )
        #expect(fixture.store.configuration.chatgpt.connected)
        #expect(await !fixture.server.isRunning)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A recovered connection keeps ownership of the desktop quit by an interrupted Codex action")
    func codexQuitDuringShutdown() async throws {
        let fixture = try await ChatGPTFixture.make(connected: true)
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .ready)
        let entered = AsyncTestGate()
        let release = AsyncTestGate()
        fixture.controller.onQuit = {
            await entered.open()
            try? await release.wait()
        }
        fixture.controller.onOpen = { environment in
            #expect(environment["CODEX_API_BASE_URL"] == nil)
            #expect(fixture.codexProfile.restoreCount == 1)
            #expect(await fixture.mainServer.isRunning)
        }
        let connect = Task { try await fixture.coordinator.connectCodex() }
        try await entered.wait(description: "Codex desktop quit entered")
        let shutdown = Task { await fixture.coordinator.shutdown() }
        _ = try await eventually(description: "Shutdown is waiting for Codex") {
            await fixture.coordinator.isShuttingDown ? true : nil
        }
        await release.open()
        _ = try await connect.value
        #expect(await shutdown.value)
        #expect(fixture.controller.running)
        #expect(fixture.events.recorded.suffix(3) == ["quit", "open-normal", "stop"])
        #expect(fixture.store.configuration.chatgpt.connected)
        #expect(fixture.store.configuration.relaunchTargets.codex)
        #expect(!fixture.store.configuration.codex.connected)
    }
}
