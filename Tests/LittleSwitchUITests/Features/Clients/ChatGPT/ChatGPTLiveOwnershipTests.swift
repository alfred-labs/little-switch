import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("ChatGPT live ownership")
struct ChatGPTLiveOwnershipTests {
    @Test("Recovery by another client stops ChatGPT before replacing the primary state")
    func otherClientRecovery() async throws {
        let fixture = try await ChatGPTFixture.make()
        _ = try await fixture.coordinator.connectChatGPT()
        let original = try #require(fixture.builder.states.first)
        await fixture.mainServer.stop()
        try await fixture.coordinator.startGateway(snapshot: original.capture())
        #expect(await !fixture.server.isRunning)
        #expect(await fixture.coordinator.gatewayState !== original)
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .needsAttention)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Reload reuses only the current listener and records the newly managed desktop")
    func unchangedGateway() async throws {
        let fixture = try await ChatGPTFixture.make()
        _ = try await fixture.coordinator.connectChatGPT()
        let firstLaunch = fixture.controller.launchID
        _ = try await fixture.coordinator.openChatGPT()
        #expect(fixture.builder.states.count == 1)
        #expect(fixture.controller.launchID != firstLaunch)
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .connected)
        _ = try await fixture.coordinator.connectCodex()
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .connected)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Startup readiness becomes attention if its recovered listener exits")
    func recoveredListenerLifetime() async throws {
        let fixture = try await ChatGPTFixture.make(connected: true)
        await fixture.server.stop()
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .needsAttention)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Polling invalidates a managed desktop that quits or is replaced normally", arguments: [false, true])
    func desktopLifetime(replacement: Bool) async throws {
        let fixture = try await ChatGPTFixture.make()
        #expect(try await fixture.coordinator.connectChatGPT().chatGPTStatus == .connected)
        fixture.controller.running = replacement
        if replacement { fixture.controller.launchID = UUID() }
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .ready)
        #expect(fixture.store.configuration.chatgpt.connected)
        #expect(await fixture.coordinator.chatGPTDesktopRestoration.requiresRestoration)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Polling reports attention when the managed listener exits")
    func listenerLifetime() async throws {
        let fixture = try await ChatGPTFixture.make()
        _ = try await fixture.coordinator.connectChatGPT()
        await fixture.server.stop()
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .needsAttention)
        #expect(fixture.store.configuration.chatgpt.connected)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Primary recovery drains the old listener before rebinding routing and shared admission")
    func primaryReplacement() async throws {
        let fixture = try await ChatGPTFixture.make()
        _ = try await fixture.coordinator.connectChatGPT()
        let original = try #require(fixture.builder.states.first)
        await fixture.mainServer.stop()
        let stopping = AsyncTestGate()
        let release = AsyncTestGate()
        await fixture.server.setOnStop {
            await stopping.open()
            try? await release.wait()
        }
        let reload = Task { try await fixture.coordinator.openChatGPT() }
        do {
            try await stopping.wait(description: "Old ChatGPT listener draining")
        } catch {
            await release.open()
            _ = try await reload.value
            await fixture.server.setOnStop {}
            await fixture.coordinator.shutdown(mode: .handoff)
            throw error
        }
        #expect(fixture.builder.states.count == 1)
        await release.open()
        #expect(try await reload.value.chatGPTStatus == .connected)
        let current = try #require(await fixture.coordinator.gatewayState)
        let captured = try #require(fixture.builder.states.last)
        #expect(fixture.builder.states.count == 2)
        #expect(captured === current)
        #expect(captured !== original)
        let provider = Provider(
            name: "Replacement",
            baseURL: "http://127.0.0.1:12345",
            authMode: .none,
            models: [DiscoveredModel(id: "new-model")],
            status: .ready)
        let routing = await current.replace(providers: [provider], mappings: [:], codex: .init())
        let capturedRouting = await captured.capture()
        #expect(capturedRouting == routing)
        #expect(
            capturedRouting.codex.exposedModels(in: capturedRouting.providers)
                == routing.codex.exposedModels(in: routing.providers))
        let eventID = UUID()
        try await captured.admit(
            GatewayRequestAdmission(
                eventID: eventID,
                capture: captured.routingCapture(),
                client: .codex,
                modelIdentifier: "replacement/new-model",
                providerID: provider.id,
                targetModelID: "new-model",
                retainedBodyBytes: 1))
        let pool = await current.requestPoolSnapshot()
        #expect(pool.providers.first { $0.id == provider.id }?.runningCount == 1)
        await current.finish(eventID: eventID)
        let finishedPool = await captured.requestPoolSnapshot()
        #expect(finishedPool.providers.first { $0.id == provider.id }?.runningCount == 0)
        await current.stopAdmissions()
        await #expect(throws: GatewayState.Error.notAcceptingRequests) { try await captured.admit() }
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
