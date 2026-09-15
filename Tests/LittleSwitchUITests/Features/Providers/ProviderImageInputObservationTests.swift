import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Provider image observation preservation")
struct ProviderImageInputObservationTests {
    @Test("Refresh and tuning keep evidence but model removal, duplication and route changes do not")
    func preservation() async throws {
        let coordinator = makeCoordinator()
        var previous = Provider(
            name: "Before",
            baseURL: "https://provider.example",
            authMode: .none,
            models: [DiscoveredModel(id: "model")])
        previous.imageInputObservations = [
            ModelImageInputObservation(
                key: try ModelImageInputPolicyResolver.key(provider: previous, modelID: "model", wire: .responses),
                verdict: .verified,
                source: .visualProbe,
                observedAt: Date(timeIntervalSince1970: 1))
        ]
        var changed = previous
        changed.name = "Renamed"
        changed.models[0].contextWindowOverride = 100_000
        #expect(
            try await coordinator.imageInputObservationsForProvider(
                changed, previous: previous, credentialChanged: false)
                == previous.imageInputObservations)
        changed.models = []
        #expect(
            try await coordinator.imageInputObservationsForProvider(
                changed, previous: previous, credentialChanged: false
            ).isEmpty)
        #expect(
            try await coordinator.imageInputObservationsForProvider(previous, previous: nil, credentialChanged: false)
                .isEmpty)
        changed = previous
        changed.baseURL = "https://other.example"
        #expect(
            try await coordinator.imageInputObservationsForProvider(
                changed, previous: previous, credentialChanged: false
            ).isEmpty)
        changed = previous
        changed.responsesWireOverride = .chatCompletions
        #expect(
            try await coordinator.imageInputObservationsForProvider(
                changed, previous: previous, credentialChanged: false
            ).isEmpty)
        #expect(
            try await coordinator.imageInputObservationsForProvider(
                previous, previous: previous, credentialChanged: true
            ).isEmpty)
        previous.credentialSource = .script
        previous.credentialScriptPath = "/synthetic/script"
        #expect(
            try await coordinator.imageInputObservationsForProvider(
                previous, previous: previous, credentialChanged: true)
                == previous.imageInputObservations)
    }

    @Test("Actual refresh persists surviving evidence and removes evidence for removed models")
    func refreshPersistence() async throws {
        let provider = try fixtureProvider()
        let transport = StaticCatalogTransport()
        let store = RecordingConfigurationStore(configuration: AppConfiguration(providers: [provider]))
        let coordinator = makeCoordinator(store: store, transport: transport)
        await coordinator.loadImageObservationFixture(provider)
        let refreshed = try await coordinator.refreshProvider(id: provider.id)
        #expect(refreshed.configuration.providers.first?.imageInputObservations == provider.imageInputObservations)
        #expect(store.configuration.providers.first?.imageInputObservations == provider.imageInputObservations)
        await transport.serveCatalog(#"{"data":[{"id":"replacement"}]}"#)
        let pruned = try await coordinator.refreshProvider(id: provider.id)
        #expect(pruned.configuration.providers.first?.imageInputObservations.isEmpty == true)
        #expect(store.configuration.providers.first?.imageInputObservations.isEmpty == true)
    }

    @Test("A failed save keeps observations and releases the routing mutation guard")
    func failedSavePreservesEvidence() async throws {
        let provider = try fixtureProvider()
        let store = RecordingConfigurationStore(configuration: AppConfiguration(providers: [provider]))
        let coordinator = makeCoordinator(store: store)
        await coordinator.loadImageObservationFixture(provider)
        store.failNextSave()
        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            try await coordinator.saveProvider(
                ProviderInput(id: provider.id, name: "Edited", baseURL: provider.baseURL, authMode: .none))
        }
        #expect(await coordinator.snapshot().configuration.providers == [provider])
        #expect(store.configuration.providers == [provider])
        #expect(
            try await coordinator.gatewayRoutingMutationGuard.readCredential(
                providerID: provider.id, secretStore: MemorySecretStore()) == nil)
    }

    @Test("Invalid derived route preparation cannot leave a routing mutation active")
    func invalidRouteReleasesMutation() async throws {
        let provider = try fixtureProvider()
        let coordinator = makeCoordinator()
        await coordinator.loadImageObservationFixture(provider)
        await #expect(throws: ProviderEndpoint.Error.self) {
            try await coordinator.saveProvider(
                ProviderInput(
                    id: provider.id,
                    name: provider.name,
                    baseURL: provider.baseURL,
                    authMode: .none,
                    anthropicBaseURL: "not a URL"))
        }
        #expect(
            try await coordinator.gatewayRoutingMutationGuard.readCredential(
                providerID: provider.id, secretStore: MemorySecretStore()) == nil)
    }

    private func fixtureProvider() throws -> Provider {
        var provider = Provider(
            name: "Fixture",
            baseURL: "https://provider.example",
            authMode: .none,
            models: [DiscoveredModel(id: "applied")],
            status: .ready)
        provider.imageInputObservations = [
            ModelImageInputObservation(
                key: try ModelImageInputPolicyResolver.key(provider: provider, modelID: "applied", wire: .responses),
                verdict: .verified,
                source: .visualProbe,
                observedAt: Date(timeIntervalSince1970: 1))
        ]
        return provider
    }

    private func makeCoordinator(
        store: RecordingConfigurationStore = RecordingConfigurationStore(configuration: AppConfiguration()),
        transport: StaticCatalogTransport = StaticCatalogTransport()
    ) -> ApplicationCoordinator {
        ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: transport,
            gatewayTransport: TestGatewayTransport())
    }
}

extension ApplicationCoordinator {
    fileprivate func loadImageObservationFixture(_ provider: Provider) {
        configuration.providers = [provider]
    }
}
