import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Provider duplication coordinator")
struct ProviderDuplicationCoordinatorTests {
    @Test("Testing a duplicate privately reuses the original key without saving it")
    func testReusesKeyWithoutPersistence() async throws {
        let transport = DuplicateCatalogTransport()
        let fixture = try await ProviderDuplicationFixture.make(transport: transport)
        await transport.resetAuthorizationChecks()
        let input = fixture.input()
        let before = fixture.store.configuration

        #expect(try await fixture.coordinator.testProvider(input) == nil)

        #expect(await transport.authorizationMatched == [true])
        #expect(fixture.store.configuration == before)
        #expect(fixture.secrets.value(for: .provider(try #require(input.id))) == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Saving a duplicate discovers fresh state and stores an independent key")
    func savesIndependentCopy() async throws {
        let fixture = try await ProviderDuplicationFixture.make()
        let input = fixture.input()
        let before = fixture.store.configuration
        let copyID = try #require(input.id)

        let result = try await fixture.coordinator.saveProvider(input)
        let copy = try #require(result.configuration.providers.first { $0.id == copyID })

        #expect(result.configuration.providers.first { $0.id == fixture.source.id } == before.providers.first)
        #expect(result.configuration.mappings == before.mappings)
        #expect(copy.models == [DiscoveredModel(id: "applied", contextWindowOverride: 1_000_000)])
        #expect(copy.maximumParallelRequests == 7)
        #expect(copy.imageInputOverride == .enabled)
        #expect(copy.responsesWireOverride == .chatCompletions)
        #expect(copy.lastRefresh != fixture.source.lastRefresh)
        #expect(copy.wireProbe != fixture.source.wireProbe)
        #expect(copy.lastError == nil)
        #expect(fixture.secrets.value(for: .provider(copyID)) == "original-key")

        _ = try await fixture.coordinator.deleteProvider(id: fixture.source.id)
        #expect(fixture.secrets.value(for: .provider(copyID)) == "original-key")
        #expect(fixture.store.configuration.providers == [copy])
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A newly entered duplicate key replaces only the copy's key")
    func newKeyWins() async throws {
        let transport = DuplicateCatalogTransport(expectedCredential: "replacement-key")
        let fixture = try await ProviderDuplicationFixture.make(transport: transport)
        await transport.resetAuthorizationChecks()
        let input = fixture.input(credential: "replacement-key")

        _ = try await fixture.coordinator.testProvider(input)
        _ = try await fixture.coordinator.saveProvider(input)

        #expect(await transport.authorizationMatched == [true, true])
        #expect(fixture.secrets.value(for: .provider(try #require(input.id))) == "replacement-key")
        #expect(fixture.secrets.value(for: .provider(fixture.source.id)) == "original-key")
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A missing original key rejects Test and Save without a partial copy")
    func missingKeyRejectsCopy() async throws {
        let fixture = try await ProviderDuplicationFixture.make(credential: nil)
        let input = fixture.input()
        let before = fixture.store.configuration

        await #expect(throws: (any Error).self) {
            _ = try await fixture.coordinator.testProvider(input)
        }
        await #expect(throws: (any Error).self) {
            _ = try await fixture.coordinator.saveProvider(input)
        }

        #expect(fixture.store.configuration == before)
        #expect(fixture.secrets.value(for: .provider(try #require(input.id))) == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Creation and duplication intents cannot overwrite an existing identity")
    func rejectsExistingDestination() async throws {
        let fixture = try await ProviderDuplicationFixture.make()
        let before = fixture.store.configuration
        for intent in [ProviderMutationIntent.add, .duplicate(sourceID: fixture.source.id)] {
            var input = fixture.input(id: fixture.source.id)
            input.intent = intent
            await #expect(throws: (any Error).self) {
                _ = try await fixture.coordinator.saveProvider(input)
            }
        }

        #expect(fixture.store.configuration == before)
        #expect(fixture.secrets.value(for: .provider(fixture.source.id)) == "original-key")
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A persistence failure restores configuration and removes the copied key")
    func failedPersistenceRollsBackCopy() async throws {
        let fixture = try await ProviderDuplicationFixture.make()
        let input = fixture.input()
        let before = fixture.store.configuration
        fixture.store.failFutureSaves(at: [1])

        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.saveProvider(input)
        }

        #expect(await fixture.coordinator.snapshot().configuration == before)
        #expect(fixture.store.configuration == before)
        #expect(fixture.secrets.value(for: .provider(try #require(input.id))) == nil)
        #expect(fixture.secrets.value(for: .provider(fixture.source.id)) == "original-key")
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
