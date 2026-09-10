import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Provider duplication validation")
struct ProviderDuplicationValidationTests {
    @Test("A deleted edit identity is never silently recreated")
    func editRequiresExistingIdentity() async throws {
        let fixture = try await ProviderDuplicationFixture.make()
        var input = fixture.input()
        input.intent = .edit

        await #expect(throws: ApplicationCoordinator.Error.providerMutationSuperseded) {
            _ = try await fixture.coordinator.saveProvider(input)
        }
        #expect(fixture.store.configuration.providers.count == 1)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A duplication request must carry its independent destination identity")
    func duplicateRequiresIdentity() async throws {
        let fixture = try await ProviderDuplicationFixture.make()
        var input = fixture.input()
        input.id = nil

        await #expect(throws: ApplicationCoordinator.Error.providerMutationSuperseded) {
            _ = try await fixture.coordinator.saveProvider(input)
        }
        #expect(fixture.store.configuration.providers.count == 1)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A source read failure stays visible and leaves the duplicate unsaved")
    func keyReadFailureIsNotSuppressed() async throws {
        let fixture = try await ProviderDuplicationFixture.make()
        let input = fixture.input()
        fixture.secrets.failNextRead()

        await #expect(throws: ScriptedSecretStore.Error.readInjected) {
            _ = try await fixture.coordinator.testProvider(input)
        }
        #expect(fixture.secrets.value(for: .provider(try #require(input.id))) == nil)
        #expect(fixture.store.configuration.providers.count == 1)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Manual authentication cannot silently clone a script's cached token")
    func changingScriptToManualRequiresKey() async throws {
        let fixture = try await ProviderDuplicationFixture.make(credentialSource: .script)
        var input = fixture.input()
        input.credentialSource = .manual

        await #expect(throws: ApplicationCoordinator.Error.missingOriginalProviderCredential) {
            _ = try await fixture.coordinator.testProvider(input)
        }
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A credential-free copy does not require or inherit the original key")
    func noAuthenticationOmitsCredential() async throws {
        let fixture = try await ProviderDuplicationFixture.make(credential: nil)
        var input = fixture.input()
        input.authMode = .none

        _ = try await fixture.coordinator.testProvider(input)
        _ = try await fixture.coordinator.saveProvider(input)

        #expect(fixture.secrets.value(for: .provider(try #require(input.id))) == nil)
        #expect(fixture.store.configuration.providers.count == 2)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A replacement key allows duplication when the original key is unavailable")
    func explicitKeyDoesNotRequireOriginalKey() async throws {
        let fixture = try await ProviderDuplicationFixture.make(credential: nil)
        let input = fixture.input(credential: "replacement-key")

        _ = try await fixture.coordinator.testProvider(input)
        _ = try await fixture.coordinator.saveProvider(input)

        #expect(fixture.secrets.value(for: .provider(try #require(input.id))) == "replacement-key")
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
