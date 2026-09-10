import Foundation
import LittleSwitchCore
import LittleSwitchSearch
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Tavily web search coordinator")
struct TavilyWebSearchCoordinatorTests {
    @Test("Connected Tavily saves persist the Tavily credential account")
    func connectedTavilySave() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make()
        defer { fixture.removeFiles() }
        let configuration = WebSearchConfiguration(provider: .tavily)

        let saved = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: configuration, credential: "tvly-key")
        )

        #expect(saved.configuration.webSearch == WebSearchConfiguration(provider: .tavily))
        #expect(try fixture.secrets.read(account: .webSearch(.tavily)) == "tvly-key")
    }

    @Test("Tavily requires a new or existing credential")
    func tavilyCredentialRequired() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make()
        defer { fixture.removeFiles() }

        await #expect(throws: ApplicationCoordinator.Error.missingTavilyCredential) {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(configuration: .tavily)
            )
        }
        #expect((try fixture.store.load()).webSearch == .disabled)
        #expect(try fixture.secrets.read(account: .webSearch(.tavily)) == nil)
    }

    @Test("Blank Tavily input preserves an existing key")
    func preservedTavilyCredential() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make(
            existingCredential: "existing-key",
            credentialProvider: .tavily
        )
        defer { fixture.removeFiles() }

        _ = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: .tavily, credential: "  ")
        )
        #expect((try fixture.store.load()).webSearch == WebSearchConfiguration(provider: .tavily))
        #expect(try fixture.secrets.read(account: .webSearch(.tavily)) == "existing-key")
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
        #expect(try fixture.secrets.read(account: .webSearch(.firecrawl)) == "fc-key")
        #expect(try fixture.secrets.read(account: .webSearch(.tavily)) == "tvly-key")

        _ = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: .firecrawlCloud, credential: "  ")
        )
        #expect(try fixture.secrets.read(account: .webSearch(.tavily)) == "tvly-key")
        #expect((try fixture.store.load()).webSearch == .firecrawlCloud)
    }
}
