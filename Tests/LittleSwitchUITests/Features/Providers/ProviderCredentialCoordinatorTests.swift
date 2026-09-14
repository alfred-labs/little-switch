import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Provider credential coordinator")
struct ProviderCredentialCoordinatorTests {
    @Test("A provider saves with or without a credential, and keeps the saved one")
    func providerSavesWithOrWithoutCredential() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(connected: false)
        defer { fixture.removeFiles() }

        _ = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Unauthenticated",
                baseURL: "http://127.0.0.1:8000",
                authMode: .none
            ))

        let saved = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "OpenAI Compatible",
                baseURL: "http://127.0.0.1:8000",
                authMode: .bearer
            ))

        // An empty credential is a provider that needs none, not a refusal.
        #expect(saved.configuration.providers.first?.authMode == .bearer)
        #expect(try fixture.secrets.read(providerID: fixture.providerID) == nil)

        _ = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "OpenAI Compatible",
                baseURL: "http://127.0.0.1:8000",
                authMode: .bearer,
                credential: "secret"
            ))

        #expect(try fixture.secrets.read(providerID: fixture.providerID) == "secret")

        // Saving again without typing one keeps what the keychain holds.
        _ = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "OpenAI Compatible",
                baseURL: "http://127.0.0.1:8000",
                authMode: .bearer
            ))

        #expect(try fixture.secrets.read(providerID: fixture.providerID) == "secret")

        // Switching to no authentication forgets it.
        _ = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "OpenAI Compatible",
                baseURL: "http://127.0.0.1:8000",
                authMode: .none
            ))

        #expect(try fixture.secrets.read(providerID: fixture.providerID) == nil)
    }
}
