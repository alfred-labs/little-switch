import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Provider duplication concurrency")
struct ProviderDuplicationConcurrencyTests {
    @Test("A source removed during discovery cannot produce a partial duplicate")
    func sourceRemovedWhileSaving() async throws {
        let transport = DuplicateCatalogTransport()
        let fixture = try await ProviderDuplicationFixture.make(transport: transport)
        let input = fixture.input()
        await transport.suspendNextProbe()
        let save = Task { try await fixture.coordinator.saveProvider(input) }
        try await transport.waitForProbe()

        _ = try await fixture.coordinator.deleteProvider(id: fixture.source.id)
        await transport.releaseProbe()

        await #expect(throws: (any Error).self) { _ = try await save.value }
        #expect(fixture.store.configuration.providers.isEmpty)
        #expect(fixture.secrets.value(for: .provider(try #require(input.id))) == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Two copies with the same normalized name cannot both persist")
    func concurrentNameCollision() async throws {
        let transport = DuplicateCatalogTransport()
        let fixture = try await ProviderDuplicationFixture.make(transport: transport)
        let firstInput = fixture.input()
        await transport.suspendNextProbe()
        let firstSave = Task { try await fixture.coordinator.saveProvider(firstInput) }
        try await transport.waitForProbe()
        var secondInput = fixture.input()
        secondInput.name = " Z.AI COPY "

        _ = try await fixture.coordinator.saveProvider(secondInput)
        await transport.releaseProbe()

        await #expect(throws: ApplicationCoordinator.Error.duplicateProviderName) {
            _ = try await firstSave.value
        }
        #expect(fixture.store.configuration.providers.count == 2)
        #expect(fixture.secrets.value(for: .provider(try #require(firstInput.id))) == nil)
        #expect(fixture.secrets.value(for: .provider(try #require(secondInput.id))) == "original-key")
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("An unavailable source rejects testing and saving even with a new key")
    func missingSource() async throws {
        let fixture = try await ProviderDuplicationFixture.make()
        let input = fixture.input(credential: "new-key")
        _ = try await fixture.coordinator.deleteProvider(id: fixture.source.id)

        await #expect(throws: (any Error).self) {
            _ = try await fixture.coordinator.testProvider(input)
        }
        await #expect(throws: (any Error).self) {
            _ = try await fixture.coordinator.saveProvider(input)
        }
        #expect(fixture.store.configuration.providers.isEmpty)
        #expect(fixture.secrets.value(for: .provider(try #require(input.id))) == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Duplicating a script executes fresh credentials for the new identity")
    func resolvesScriptAfresh() async throws {
        let runner = DuplicateScriptRunner()
        let fixture = try await ProviderDuplicationFixture.make(
            credentialSource: .script,
            transport: DuplicateCatalogTransport(expectedCredential: "fresh-script-key"),
            scriptRunner: runner
        )
        let input = fixture.input()
        await fixture.coordinator.recordScriptOutcome(
            providerID: fixture.source.id,
            CredentialRefreshOutcome(kind: .refreshed, standardError: "Original output")
        )

        #expect(try await fixture.coordinator.testProvider(input) == "Fresh run")
        #expect(fixture.secrets.value(for: .provider(try #require(input.id))) == nil)
        let testOutputs = await fixture.coordinator.snapshot().lastScriptOutputs
        #expect(testOutputs[try #require(input.id)] == "Fresh run")
        _ = try await fixture.coordinator.saveProvider(input)

        #expect(await runner.calls == ["/tmp/provider-login.sh", "/tmp/provider-login.sh"])
        #expect(fixture.secrets.value(for: .provider(try #require(input.id))) == "fresh-script-key")
        #expect(fixture.secrets.value(for: .provider(fixture.source.id)) == "original-key")
        let outputs = await fixture.coordinator.snapshot().lastScriptOutputs
        #expect(outputs[fixture.source.id] == "Original output")
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A source key removed while probing is not resurrected in the copy")
    func keyRemovedWhileSaving() async throws {
        let transport = DuplicateCatalogTransport()
        let fixture = try await ProviderDuplicationFixture.make(transport: transport)
        let input = fixture.input()
        let before = fixture.store.configuration
        await transport.suspendNextProbe()
        let save = Task { try await fixture.coordinator.saveProvider(input) }
        try await transport.waitForProbe()

        try fixture.secrets.delete(providerID: fixture.source.id)
        await transport.releaseProbe()

        await #expect(throws: (any Error).self) { _ = try await save.value }
        #expect(fixture.store.configuration == before)
        #expect(fixture.secrets.value(for: .provider(try #require(input.id))) == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A rotated source key requires a fresh duplication attempt")
    func keyRotatedWhileSaving() async throws {
        let transport = DuplicateCatalogTransport()
        let fixture = try await ProviderDuplicationFixture.make(transport: transport)
        let input = fixture.input()
        let before = fixture.store.configuration
        await transport.suspendNextProbe()
        let save = Task { try await fixture.coordinator.saveProvider(input) }
        try await transport.waitForProbe()

        try fixture.secrets.write("rotated-key", providerID: fixture.source.id)
        await transport.releaseProbe()

        await #expect(throws: ApplicationCoordinator.Error.providerMutationSuperseded) {
            _ = try await save.value
        }
        #expect(fixture.store.configuration == before)
        #expect(fixture.secrets.value(for: .provider(try #require(input.id))) == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
