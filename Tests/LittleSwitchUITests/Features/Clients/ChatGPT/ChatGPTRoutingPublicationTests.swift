import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Chat routing publication during desktop relaunch")
struct ChatGPTRoutingPublicationTests {
    enum Action: CaseIterable { case connect, apply, disconnect }

    @Test("Background evidence cannot replace the newly applied route", arguments: Action.allCases)
    func observationDuringLaunch(_ action: Action) async throws {
        let fixture = try await ChatGPTFixture.make()
        if action != .connect { _ = try await fixture.coordinator.connectDesktopClients() }
        let provider = try #require(fixture.store.configuration.providers.first)
        if action != .disconnect {
            _ = try await fixture.coordinator.setChatGPTModel(.init(providerID: provider.id, modelID: "replacement"))
        }
        let generation = UUID()
        await fixture.coordinator.setChatTestObservationGeneration(generation, providerID: provider.id)
        let observation = ModelImageInputObservation(
            key: try ModelImageInputPolicyResolver.key(provider: provider, modelID: "applied", wire: .responses),
            verdict: .verified,
            source: .visualProbe,
            observedAt: Date()
        )
        let chosen = await fixture.coordinator.snapshot().configuration.chatgpt.model
        fixture.controller.onOpen = { _ in
            await fixture.coordinator.acceptImageInputObservation(observation, generation: generation)
            let state = fixture.builder.states.last
            let duringLaunch = await state?.capture()
            #expect(duringLaunch?.chatgpt.model == chosen)
            #expect(duringLaunch?.chatgpt.connected == (action != .disconnect))
            #expect(duringLaunch?.codex.connected == (action != .disconnect))
        }
        let result: CoordinatorSnapshot
        switch action {
        case .connect: result = try await fixture.coordinator.connectDesktopClients()
        case .apply: result = try await fixture.coordinator.applyChatGPTSettings()
        case .disconnect: result = try await fixture.coordinator.disconnectDesktopClients()
        }
        let state = try #require(fixture.builder.states.last)
        let route = await state.capture()
        #expect(route.chatgpt == result.configuration.chatgpt)
        #expect(route.codex == fixture.store.configuration.codex)
        #expect(route.providers == fixture.store.configuration.providers)
        #expect(fixture.store.configuration.providers[0].imageInputObservations == [observation])
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("An unrelated change during opening survives cancellation of the stale connection plan")
    func concurrentSettings() async throws {
        let fixture = try await ChatGPTFixture.make()
        let previous = fixture.store.configuration
        var changed = false
        fixture.controller.onOpen = { _ in
            guard !changed else { return }
            changed = true
            _ = try? await fixture.coordinator.setAutoMode(!previous.autoMode)
        }
        await #expect(throws: (any Error).self) { try await fixture.coordinator.connectDesktopClients() }
        var expected = previous
        expected.autoMode.toggle()
        #expect(fixture.store.configuration == expected)
        #expect(await fixture.coordinator.snapshot().configuration == expected)
        #expect(fixture.controller.running)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}

extension ApplicationCoordinator {
    fileprivate func setChatTestObservationGeneration(_ generation: UUID, providerID: UUID) {
        imageProbeGenerations[providerID] = generation
    }
}
