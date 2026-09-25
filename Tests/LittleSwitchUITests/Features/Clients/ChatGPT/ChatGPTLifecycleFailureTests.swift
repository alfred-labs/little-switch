import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("ChatGPT lifecycle failures and restoration")
struct ChatGPTLifecycleFailureTests {
    @Test("User quit restores the shared Codex profile before reopening normally and remembers its intent")
    func sharedProfileShutdown() async throws {
        let fixture = try await ChatGPTFixture.make()
        _ = try await fixture.coordinator.connectCodex()
        _ = try await fixture.coordinator.connectChatGPT()
        fixture.controller.onOpen = { environment in
            if environment["CODEX_API_BASE_URL"] == nil {
                #expect(fixture.codexProfile.restoreCount == 1)
                #expect(await fixture.mainServer.isRunning)
            }
        }
        #expect(await fixture.coordinator.shutdown())
        #expect(fixture.store.configuration.relaunchTargets.codex)
        #expect(!fixture.store.configuration.codex.connected)
        #expect(fixture.store.configuration.chatgpt.connected)
    }

    @Test("A failed shared profile restoration cancels shutdown and keeps the listener")
    func sharedProfileShutdownFailure() async throws {
        let fixture = try await ChatGPTFixture.make()
        _ = try await fixture.coordinator.connectCodex()
        _ = try await fixture.coordinator.connectChatGPT()
        fixture.codexProfile.failNextRestore()
        let eventCount = fixture.events.recorded.count
        #expect(await !fixture.coordinator.shutdown())
        #expect(await fixture.server.isRunning)
        #expect(await fixture.mainServer.isRunning)
        #expect(fixture.store.configuration.codex.connected)
        #expect(fixture.store.configuration.chatgpt.connected)
        #expect(!fixture.events.recorded.dropFirst(eventCount).contains("open-normal"))
        #expect(await fixture.coordinator.shutdown())
    }

    @Test(
        "Prerequisites reject before quitting the desktop",
        arguments: ["models", "controller", "trust", "environment", "listener"]
    )
    func prerequisites(_ failure: String) async throws {
        let fixture = try await ChatGPTFixture.make(
            trusted: failure != "trust",
            hasModels: failure != "models",
            hasController: failure != "controller",
            environment: failure == "environment" ? ["CODEX_API_BASE_URL": "https://example.com"] : [:]
        )
        if failure == "listener" { await fixture.server.failNextStart() }
        await #expect(throws: (any Error).self) { try await fixture.coordinator.connectChatGPT() }
        #expect(!fixture.events.recorded.contains("quit"))
        #expect(!fixture.store.configuration.chatgpt.connected)
        #expect(await fixture.mainServer.isRunning)
        #expect(await !fixture.server.isRunning)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Quit refusal leaves the original app untouched")
    func quitRefusal() async throws {
        let fixture = try await ChatGPTFixture.make()
        fixture.controller.failQuit = true
        await #expect(throws: (any Error).self) { try await fixture.coordinator.connectChatGPT() }
        #expect(fixture.controller.running)
        #expect(fixture.controller.environments.isEmpty)
        #expect(await !fixture.server.isRunning)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Launch failure reopens normal desktop routing")
    func launchFailure() async throws {
        let fixture = try await ChatGPTFixture.make()
        fixture.controller.failOpen = true
        await #expect(throws: (any Error).self) { try await fixture.coordinator.connectChatGPT() }
        #expect(fixture.events.recorded == ["trust", "start", "quit", "open-normal", "stop"])
        #expect(!fixture.store.configuration.chatgpt.connected)
        #expect(fixture.controller.running)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Disconnect restores normal launch and preserves the shared service and model configuration")
    func disconnect() async throws {
        let fixture = try await ChatGPTFixture.make()
        let connected = try await fixture.coordinator.connectDesktopClients()
        let result = try await fixture.coordinator.disconnectDesktopClients()
        var expected = connected.configuration
        expected.codex.connected = false
        expected.chatgpt.connected = false
        #expect(result.configuration == expected)
        #expect(result.chatGPTStatus == .disconnected)
        #expect(fixture.controller.environments.last == ["TEST_PARENT": "inherited"])
        #expect(await fixture.mainServer.isRunning)
        #expect(await !fixture.server.isRunning)
        #expect(fixture.events.recorded.suffix(3) == ["quit", "open-normal", "stop"])
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test(
        "Disconnect failures retain restoration responsibility and the service",
        arguments: ["quit", "save", "launch"]
    )
    func disconnectFailure(_ failure: String) async throws {
        let fixture = try await ChatGPTFixture.make()
        _ = try await fixture.coordinator.connectChatGPT()
        if failure == "quit" { fixture.controller.failQuit = true }
        if failure == "launch" { fixture.controller.failOpen = true }
        if failure == "save" { fixture.store.failNextSave() }
        await #expect(throws: (any Error).self) { try await fixture.coordinator.disconnectDesktopClients() }
        #expect(fixture.store.configuration.chatgpt.connected)
        #expect(await fixture.server.isRunning)
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .needsAttention)
        fixture.controller.failQuit = false
        _ = try await fixture.coordinator.disconnectDesktopClients()
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Untrusted startup preserves intent without asking for consent")
    func startupTrustRefused() async throws {
        let fixture = try await ChatGPTFixture.make(connected: true, trusted: false)
        #expect(fixture.store.configuration.chatgpt.connected)
        #expect(fixture.events.recorded.isEmpty)
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .needsAttention)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("User quit refuses termination if the desktop will not quit")
    func shutdownRefusal() async throws {
        let fixture = try await ChatGPTFixture.make()
        _ = try await fixture.coordinator.connectChatGPT()
        fixture.controller.failQuit = true
        #expect(await !fixture.coordinator.shutdown())
        #expect(await fixture.server.isRunning)
        #expect(await fixture.mainServer.isRunning)
        #expect(fixture.store.configuration.chatgpt.connected)
        fixture.controller.failQuit = false
        #expect(await fixture.coordinator.shutdown())
        #expect(fixture.events.recorded.suffix(3) == ["quit", "open-normal", "stop"])
        #expect(fixture.store.configuration.chatgpt.connected)
    }

    @Test(
        "Shutdown supersedes an in-flight connection without reopening managed routing",
        arguments: [ApplicationShutdownMode.handoff, .userQuit]
    )
    func shutdownRace(mode: ApplicationShutdownMode) async throws {
        let fixture = try await ChatGPTFixture.make()
        let entered = AsyncTestGate()
        let release = AsyncTestGate()
        fixture.controller.onQuit = {
            await entered.open()
            try? await release.wait()
        }
        let connect = Task { try await fixture.coordinator.connectChatGPT() }
        try await entered.wait(description: "ChatGPT reached desktop quit")
        await #expect(throws: (any Error).self) { try await fixture.coordinator.disconnectDesktopClients() }
        #expect(await fixture.coordinator.shutdown(mode: mode))
        await #expect(throws: (any Error).self) { try await connect.value }
        #expect(!fixture.events.recorded.contains("open-managed"))
        #expect(fixture.events.recorded.contains("open-normal") == (mode == .userQuit))
        #expect(await !fixture.server.isRunning)
        #expect(!fixture.store.configuration.chatgpt.connected)
        await release.open()
    }

    @Test("A pending Codex model draft does not block the independent Chat connection")
    func pendingCodex() async throws {
        let fixture = try await ChatGPTFixture.make()
        let connected = try await fixture.coordinator.connectCodex()
        let provider = try #require(connected.configuration.providers.first)
        _ = try await fixture.coordinator.setCodexDefaultModel(.init(providerID: provider.id, modelID: "replacement"))
        let before = fixture.codexProfile.activations
        _ = try await fixture.coordinator.connectChatGPT()
        #expect(fixture.codexProfile.activations == before)
        #expect(await fixture.coordinator.snapshot().hasPendingCodexChanges)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Codex relaunches preserve the managed ChatGPT environment until both clients disconnect")
    func codexRelaunch() async throws {
        let fixture = try await ChatGPTFixture.make()
        _ = try await fixture.coordinator.connectChatGPT()
        _ = try await fixture.coordinator.connectCodex()
        #expect(fixture.controller.environments.last?["CODEX_API_BASE_URL"] == ChatGPTLaunchEnvironment.apiBaseURL)
        try await fixture.coordinator.openDesktopApplication(.codex)
        #expect(
            fixture.controller.environments.last?["CODEX_APP_SERVER_CHATGPT_BASE_URL"]
                == ChatGPTLaunchEnvironment.apiBaseURL
        )
        #expect(fixture.controller.environments.last?["CODEX_API_BASE_URL"] == ChatGPTLaunchEnvironment.apiBaseURL)
        _ = try await fixture.coordinator.disconnectDesktopClients()
        #expect(fixture.controller.environments.last == ["TEST_PARENT": "inherited"])
        #expect(!fixture.store.configuration.codex.connected && !fixture.store.configuration.chatgpt.connected)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Older controllers reject environment launches instead of silently discarding them")
    func legacyController() async {
        let controller = TestCodexController()
        await #expect(throws: (any Error).self) { try await controller.open(environment: ["TEST": "value"]) }
        #expect(controller.openCount == 0)
    }
}
