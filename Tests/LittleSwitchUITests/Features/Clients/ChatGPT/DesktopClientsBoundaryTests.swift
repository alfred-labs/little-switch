import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Shared desktop transaction boundaries")
struct DesktopClientsBoundaryTests {
    @Test("A failed profile rollback remains recoverable", arguments: [false, true])
    func retryProfileRestoration(shutdown: Bool) async throws {
        let fixture = try await ChatGPTFixture.make()
        let previous = fixture.store.configuration
        fixture.store.failNextSave()
        fixture.codexProfile.failNextRestore()
        await #expect(throws: ChatGPTConnectionError.rollbackFailed) {
            try await fixture.coordinator.connectDesktopClients()
        }
        #expect(try fixture.codexProfile.isActive(providers: previous.providers, configuration: previous.codex))
        if shutdown {
            #expect(await fixture.coordinator.shutdown())
        } else {
            _ = try await fixture.coordinator.disconnectDesktopClients()
        }
        #expect(try !fixture.codexProfile.isActive(providers: previous.providers, configuration: previous.codex))
        #expect(!fixture.store.configuration.codex.connected)
        #expect(!fixture.store.configuration.chatgpt.connected)
        #expect(fixture.controller.running)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Cancellation while the desktop is quitting still restores the application", arguments: [false, true])
    func interruptedQuit(disconnect: Bool) async throws {
        let fixture = try await ChatGPTFixture.make()
        if disconnect { _ = try await fixture.coordinator.connectDesktopClients() }
        let previous = fixture.store.configuration
        let entered = AsyncTestGate()
        let release = AsyncTestGate()
        var firstQuit = true
        fixture.controller.onQuit = {
            if firstQuit {
                firstQuit = false
                fixture.controller.running = false
                await entered.open()
                try await release.wait()
            }
        }
        let operation = Task {
            if disconnect { return try await fixture.coordinator.disconnectDesktopClients() }
            return try await fixture.coordinator.connectDesktopClients()
        }
        try await entered.wait(description: "desktop accepted termination")
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(fixture.controller.running)
        #expect(fixture.store.configuration == previous)
        #expect(await fixture.server.isRunning == disconnect)
        await release.open()
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Rollback quits the candidate desktop before restoring its profile")
    func quitFlushCannotOverwriteRollback() async throws {
        let fixture = try await ChatGPTFixture.make()
        let previous = fixture.store.configuration
        fixture.controller.onQuit = {
            // Simulate Desktop's real quit-time flush after a managed launch.
            if fixture.controller.environments.contains(where: { $0["CODEX_API_BASE_URL"] != nil }) {
                try? fixture.codexProfile.activate(providers: previous.providers, configuration: .init(connected: true))
            }
        }
        fixture.store.failNextSave()
        await #expect(throws: (any Error).self) { try await fixture.coordinator.connectDesktopClients() }
        #expect(try !fixture.codexProfile.isActive(providers: previous.providers, configuration: previous.codex))
        #expect(fixture.store.configuration == previous)
        #expect(fixture.controller.running)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Disconnect is idle when neither connection owns the desktop")
    func disconnectedIsIdle() async throws {
        let fixture = try await ChatGPTFixture.make()
        let previous = fixture.store.configuration
        let snapshot = try await fixture.coordinator.disconnectDesktopClients()
        #expect(snapshot.configuration == previous)
        #expect(fixture.events.recorded.isEmpty)
        #expect(fixture.store.configuration == previous)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Cancellation restores both clients and rejects overlapping edits", arguments: [false, true])
    func cancellation(disconnect: Bool) async throws {
        let fixture = try await ChatGPTFixture.make()
        if disconnect { _ = try await fixture.coordinator.connectDesktopClients() }
        let previous = fixture.store.configuration
        let entered = AsyncTestGate()
        let release = AsyncTestGate()
        fixture.controller.onQuit = {
            await entered.open()
            try? await release.wait()
        }
        let operation = Task {
            if disconnect { return try await fixture.coordinator.disconnectDesktopClients() }
            return try await fixture.coordinator.connectDesktopClients()
        }
        try await entered.wait(description: "shared desktop reached quit")
        await #expect(throws: ChatGPTConnectionError.operationInProgress) {
            try await fixture.coordinator.connectCodex()
        }
        await #expect(throws: ChatGPTConnectionError.operationInProgress) {
            try await fixture.coordinator.setChatGPTModel(previous.chatgpt.model)
        }
        operation.cancel()
        await release.open()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(fixture.store.configuration == previous)
        #expect(fixture.controller.running)
        #expect(await fixture.server.isRunning == disconnect)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Shutdown takes ownership of a shared relaunch", arguments: [ApplicationShutdownMode.userQuit, .handoff])
    func shutdown(mode: ApplicationShutdownMode) async throws {
        let fixture = try await ChatGPTFixture.make()
        let entered = AsyncTestGate()
        let release = AsyncTestGate()
        fixture.controller.onQuit = {
            await entered.open()
            try? await release.wait()
        }
        let operation = Task { try await fixture.coordinator.connectDesktopClients() }
        try await entered.wait(description: "shared desktop reached quit before shutdown")
        #expect(await fixture.coordinator.shutdown(mode: mode))
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(!fixture.store.configuration.codex.connected)
        #expect(!fixture.store.configuration.chatgpt.connected)
        #expect(!fixture.events.recorded.contains("open-managed"))
        #expect(fixture.events.recorded.contains("open-normal") == (mode == .userQuit))
        #expect(await !fixture.server.isRunning)
        await release.open()
    }

    @Test("Failed reload restores the previous live model and retains the draft")
    func liveModelRollback() async throws {
        let fixture = try await ChatGPTFixture.make()
        let previous = try await fixture.coordinator.connectDesktopClients().configuration
        let provider = try #require(previous.providers.first)
        let choice = ModelMapping(providerID: provider.id, modelID: "replacement")
        _ = try await fixture.coordinator.setChatGPTModel(choice)
        fixture.controller.failOpen = true
        await #expect(throws: (any Error).self) { try await fixture.coordinator.connectDesktopClients() }
        #expect(fixture.store.configuration == previous)
        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.configuration.chatgpt.model == choice)
        #expect(snapshot.hasPendingChatGPTChanges)
        let state = try #require(fixture.builder.states.last)
        #expect(await state.capture().chatgpt == previous.chatgpt)
        #expect(fixture.controller.environments.last?["CODEX_API_BASE_URL"] == ChatGPTLaunchEnvironment.apiBaseURL)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Legacy connected intent without a model requests attention while keeping native Chat available")
    func legacySelection() async throws {
        let fixture = try await ChatGPTFixture.make(connected: true, hasChatModel: false)
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .needsAttention)
        #expect(await fixture.server.isRunning)
        #expect(fixture.events.recorded == ["start"])
        #expect(fixture.store.configuration.chatgpt.model == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
