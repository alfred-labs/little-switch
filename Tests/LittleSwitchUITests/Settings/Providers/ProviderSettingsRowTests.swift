import LittleSwitchCommon
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Provider settings row")
struct ProviderSettingsRowTests {
    @Test("Model counts use the singular form for one model")
    func singularModelCount() async throws {
        let provider = Provider(
            name: "Local",
            baseURL: "https://example.com",
            authMode: .none,
            models: [DiscoveredModel(id: "model")]
        )
        let host = MenuControlTestHost(
            ProviderSettingsRow(provider: provider, scriptFailure: nil), width: 600, height: 80)
        defer { host.close() }
        try await host.activateAccessibility()

        let lastText = host.textContent.last ?? ""
        #expect(lastText.hasSuffix(L10n.string("\(1) model")))
    }
}
