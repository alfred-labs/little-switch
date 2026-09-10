import Foundation
import LittleSwitchCore
import LittleSwitchSearch
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Brave web search coordinator")
struct BraveWebSearchCoordinatorTests {
    @Test("Connected Brave saves persist the Brave credential account")
    func connectedBraveSave() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make()
        defer { fixture.removeFiles() }
        let configuration = WebSearchConfiguration(provider: .brave)

        let saved = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: configuration, credential: "brave-key")
        )

        #expect(saved.configuration.webSearch == WebSearchConfiguration(provider: .brave))
        #expect(try fixture.secrets.read(account: .webSearch(.brave)) == "brave-key")
    }

    @Test("Brave requires a new or existing credential")
    func braveCredentialRequired() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make()
        defer { fixture.removeFiles() }

        await #expect(throws: ApplicationCoordinator.Error.missingBraveCredential) {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(configuration: .brave)
            )
        }
        #expect((try fixture.store.load()).webSearch == .disabled)
        #expect(try fixture.secrets.read(account: .webSearch(.brave)) == nil)
    }

    @Test("Blank Brave input preserves an existing key")
    func preservedBraveCredential() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make(
            existingCredential: "existing-key",
            credentialProvider: .brave
        )
        defer { fixture.removeFiles() }

        _ = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: .brave, credential: "  ")
        )
        #expect((try fixture.store.load()).webSearch == WebSearchConfiguration(provider: .brave))
        #expect(try fixture.secrets.read(account: .webSearch(.brave)) == "existing-key")
    }

    @Test("Switching providers preserves each provider's stored key")
    func switchingProvidersPreservesEachKey() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make()
        defer { fixture.removeFiles() }

        _ = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: .firecrawlCloud, credential: "fc-key")
        )
        _ = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: .tavily, credential: "tvly-key")
        )
        _ = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: .brave, credential: "brave-key")
        )
        #expect(try fixture.secrets.read(account: .webSearch(.firecrawl)) == "fc-key")
        #expect(try fixture.secrets.read(account: .webSearch(.tavily)) == "tvly-key")
        #expect(try fixture.secrets.read(account: .webSearch(.brave)) == "brave-key")

        _ = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: .firecrawlCloud, credential: "  ")
        )
        #expect(try fixture.secrets.read(account: .webSearch(.brave)) == "brave-key")
        #expect((try fixture.store.load()).webSearch == .firecrawlCloud)
    }
}
