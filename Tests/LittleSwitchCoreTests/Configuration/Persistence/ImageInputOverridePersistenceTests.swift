import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Image input override persistence")
struct ImageInputOverridePersistenceTests {
    @Test(
        "A provider's image input override round-trips",
        arguments: [
            ProviderImageInputOverride.enabled,
            ProviderImageInputOverride.disabled,
            nil,
        ])
    func imageInputOverrideRoundTrip(imageInputOverride: ProviderImageInputOverride?) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = AppConfiguration(
            providers: [
                Provider(
                    name: "Vision",
                    baseURL: "https://example.com",
                    authMode: .bearer,
                    imageInputOverride: imageInputOverride
                )
            ]
        )
        let store = ConfigurationStore(
            fileURL: directory.appending(path: "config.json"),
            backupDirectory: directory.appending(path: "backups")
        )

        try store.save(configuration)
        #expect(try store.load() == configuration)
        #expect(
            try store.load().providers.first?.imageInputOverride == imageInputOverride
        )
    }

}
