import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Shared Codex and ChatGPT connection")
struct DesktopClientsConnectionTests {
    @Test("A missing Chat choice rejects before trust, profile writes or desktop quit")
    func missingChoice() async throws {
        let fixture = try await ChatGPTFixture.make(hasChatModel: false)
        await #expect(throws: ChatGPTConnectionError.self) { try await fixture.coordinator.connectDesktopClients() }
        #expect(fixture.events.recorded.isEmpty)
        #expect(fixture.codexProfile.activations.isEmpty)
        #expect(!fixture.store.configuration.codex.connected)
        #expect(!fixture.store.configuration.chatgpt.connected)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("One relaunch activates both surfaces and saves only after opening")
    func connect() async throws {
        let fixture = try await ChatGPTFixture.make()
        fixture.controller.onOpen = { _ in
            #expect(!fixture.store.configuration.codex.connected)
            #expect(!fixture.store.configuration.chatgpt.connected)
            #expect(fixture.codexProfile.activations.count == 1)
        }
        let result = try await fixture.coordinator.connectDesktopClients()
        #expect(result.configuration.codex.connected)
        #expect(result.configuration.chatgpt.connected)
        #expect(result.chatGPTStatus == .connected)
        #expect(fixture.events.recorded == ["trust", "start", "quit", "open-managed"])
        #expect(fixture.store.configuration == result.configuration)
        #expect(await fixture.mainServer.isRunning)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Disconnect restores both connections in one relaunch")
    func disconnect() async throws {
        let fixture = try await ChatGPTFixture.make()
        _ = try await fixture.coordinator.connectCodex()
        let connected = try await fixture.coordinator.connectChatGPT()
        let before = fixture.events.recorded.count
        let result = try await fixture.coordinator.disconnectDesktopClients()
        var expected = connected.configuration
        expected.codex.connected = false
        expected.chatgpt.connected = false
        #expect(result.configuration == expected)
        #expect(result.chatGPTStatus == .disconnected)
        #expect(fixture.events.recorded.dropFirst(before) == ["quit", "open-normal", "stop"])
        #expect(fixture.codexProfile.restoreCount == 1)
        #expect(await !fixture.server.isRunning)
        #expect(await fixture.mainServer.isRunning)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test(
        "Activation failures restore the profile, saved intent and desktop",
        arguments: ["listener", "profile", "open", "save"])
    func connectRollback(_ failure: String) async throws {
        let fixture = try await ChatGPTFixture.make()
        let previous = fixture.store.configuration
        if failure == "listener" { await fixture.server.failNextStart() }
        if failure == "profile" { fixture.codexProfile.failNextActivation() }
        if failure == "open" { fixture.controller.failOpen = true }
        if failure == "save" { fixture.store.failNextSave() }
        await #expect(throws: (any Error).self) { try await fixture.coordinator.connectDesktopClients() }
        #expect(fixture.store.configuration == previous)
        #expect(await fixture.coordinator.snapshot().configuration == previous)
        #expect(fixture.controller.running)
        #expect(await !fixture.server.isRunning)
        #expect(await fixture.mainServer.isRunning)
        if failure == "listener" {
            #expect(!fixture.events.recorded.contains("quit"))
            #expect(fixture.codexProfile.activations.isEmpty)
        } else {
            #expect(fixture.codexProfile.restoreCount == 1)
            #expect(fixture.controller.environments.last?["CODEX_API_BASE_URL"] == nil)
        }
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Disconnect failures restore both connected states", arguments: ["profile", "open", "save"])
    func disconnectRollback(_ failure: String) async throws {
        let fixture = try await ChatGPTFixture.make()
        let previous = try await fixture.coordinator.connectDesktopClients().configuration
        if failure == "profile" { fixture.codexProfile.failNextRestore() }
        if failure == "open" { fixture.controller.failOpen = true }
        if failure == "save" { fixture.store.failNextSave() }
        await #expect(throws: (any Error).self) { try await fixture.coordinator.disconnectDesktopClients() }
        #expect(fixture.store.configuration == previous)
        #expect(await fixture.coordinator.snapshot().configuration == previous)
        #expect(await fixture.server.isRunning)
        #expect(fixture.controller.environments.last?["CODEX_API_BASE_URL"] == ChatGPTLaunchEnvironment.apiBaseURL)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
