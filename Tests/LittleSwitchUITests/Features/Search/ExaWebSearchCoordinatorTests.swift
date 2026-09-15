import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchSearch
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Exa web search coordinator")
struct ExaWebSearchCoordinatorTests {
    @Test("Exa saves its own key and updates live routing without restarting Claude")
    func saveExa() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make(existingCredential: "firecrawl-key")
        defer { fixture.removeFiles() }
        let configuration = WebSearchConfiguration(provider: .exa, resultsLimit: 100, maximumUses: 4)
        let saved = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: configuration, credential: "  exa-key\n")
        )
        #expect(saved.configuration.webSearch == configuration)
        #expect((try fixture.store.load()).webSearch == configuration)
        #expect(await fixture.gatewayState.capture().webSearch == configuration)
        #expect(try fixture.secrets.read(account: .webSearch(.exa)) == "exa-key")
        #expect(try fixture.secrets.read(account: .webSearch(.firecrawl)) == "firecrawl-key")
        #expect(fixture.controller.quitCount == 0)
        #expect(fixture.controller.openCount == 0)
    }

    @Test("Exa requires a key even when another provider already has one")
    func requiredKey() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make(existingCredential: "firecrawl-key")
        defer { fixture.removeFiles() }
        await #expect(throws: ApplicationCoordinator.Error.missingExaCredential) {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(configuration: WebSearchConfiguration(provider: .exa)))
        }
        #expect((try fixture.store.load()).webSearch == .disabled)
        #expect(try fixture.secrets.read(account: .webSearch(.exa)) == nil)
        #expect(
            ApplicationCoordinator.Error.missingExaCredential.errorDescription
                == L10n.string("Enter an Exa API key for web search.")
        )
    }

    @Test("Switching away from Exa and back with blank input preserves independent keys")
    func preserveKeys() async throws {
        let fixture = try await WebSearchCoordinatorFixture.make(
            existingCredential: "exa-key", credentialProvider: .exa)
        defer { fixture.removeFiles() }
        for provider in [WebSearchProvider.firecrawl, .tavily, .brave] {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(
                    configuration: WebSearchConfiguration(provider: provider), credential: "\(provider.rawValue)-key")
            )
        }
        _ = try await fixture.coordinator.saveWebSearch(
            WebSearchInput(configuration: WebSearchConfiguration(provider: .exa), credential: "  "))
        #expect((try fixture.store.load()).webSearch == WebSearchConfiguration(provider: .exa))
        for provider in [WebSearchProvider.firecrawl, .tavily, .brave, .exa] {
            #expect(try fixture.secrets.read(account: .webSearch(provider)) == "\(provider.rawValue)-key")
        }
    }

    @Test("A failed Exa save restores settings, key and routing", arguments: [false, true])
    func rollback(existingKey: Bool) async throws {
        let fixture = try await WebSearchCoordinatorFixture.make(
            existingCredential: existingKey ? "old-exa-key" : nil, credentialProvider: .exa
        )
        defer { fixture.removeFiles() }
        let before = try fixture.store.load()
        fixture.store.failNextSave()
        await #expect(throws: FailNextConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.saveWebSearch(
                WebSearchInput(configuration: WebSearchConfiguration(provider: .exa), credential: "new-exa-key"))
        }
        #expect((await fixture.coordinator.snapshot()).configuration == before)
        #expect(try fixture.store.load() == before)
        #expect(await fixture.gatewayState.capture().webSearch == before.webSearch)
        #expect(try fixture.secrets.read(account: .webSearch(.exa)) == (existingKey ? "old-exa-key" : nil))
    }

    @Test("Exa drafts expose the provider limits and clear typed keys on provider changes")
    func exaDraft() {
        var draft = WebSearchDraft(configuration: WebSearchConfiguration(provider: .firecrawl, resultsLimit: 80))
        draft.credential = "previous-key"
        draft.select(provider: .exa)
        #expect(draft.resultsRange == 1...100)
        #expect(draft.input == WebSearchInput(configuration: WebSearchConfiguration(provider: .exa, resultsLimit: 80)))
        #expect(draft.connectionTitle == L10n.resource("Exa connection"))
        #expect(
            draft.credentialPresentation
                == WebSearchCredentialPresentation(
                    placeholder: L10n.resource("Leave blank to keep the saved key"),
                    accessibilityHint: L10n.resource("Required for Exa. Leave blank to keep the saved key.")
                ))
        draft.credential = "  exa-key\n"
        draft.select(provider: .exa)
        #expect(draft.input.credential == "exa-key")
        draft.select(provider: .brave)
        #expect(draft.credential.isEmpty)
        #expect(draft.resultsLimit == 20)
    }
}
