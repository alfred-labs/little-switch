import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Credential refresh interval persistence")
struct RefreshIntervalPersistenceTests {
    @Test("A provider's script refresh period round-trips and stays optional")
    func credentialRefreshIntervalRoundTrip() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let withInterval = AppConfiguration(
            providers: [
                Provider(
                    name: "Vault",
                    baseURL: "https://vault.example.com",
                    authMode: .bearer,
                    credentialSource: .script,
                    credentialRefreshInterval: 900
                ),
                Provider(
                    name: "Plain",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none
                ),
            ]
        )
        let store = ConfigurationStore(
            fileURL: directory.appending(path: "config.json"),
            backupDirectory: directory.appending(path: "backups")
        )

        try store.save(withInterval)
        #expect(try store.load() == withInterval)

        // A configuration written before the field existed decodes it as nil.
        let data = try Data(contentsOf: store.fileURL)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var providers = try #require(object["providers"] as? [[String: Any]])
        for index in providers.indices {
            providers[index].removeValue(forKey: "credentialRefreshInterval")
        }
        object["providers"] = providers
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        try legacyData.write(to: store.fileURL, options: .atomic)
        let loaded = try store.load()
        #expect(loaded.providers.map(\.credentialRefreshInterval) == [nil, nil])
    }

}
