import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Search configuration persistence")
struct SearchConfigurationPersistenceTests {
    @Test("The application keeps its schema and disabled search default")
    func defaults() {
        #expect(AppConfiguration().version == 9)
        #expect(AppConfiguration().webSearch == .disabled)
    }

    @Test("Exa settings round-trip through application persistence")
    func exaRoundTrip() throws {
        var configuration = AppConfiguration()
        configuration.webSearch = WebSearchConfiguration(provider: .exa)
        let encoded = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(AppConfiguration.self, from: encoded) == configuration)
        #expect(SecretAccount.webSearch(.exa).keychainAccount == "web-search.exa")
    }
}
