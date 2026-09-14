import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Provider thinking configuration")
struct ProviderThinkingConfigurationTests {
    @Test("Stored provider configuration retains the selected disabled-thinking compatibility setting")
    func preservesSelectedOverride() throws {
        let provider = Provider(name: "example", baseURL: "https://example.com", authMode: .none)
        let configuration = AppConfiguration(providers: [provider])
        var root = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any]
        )
        var storedProviders = try #require(root["providers"] as? [[String: Any]])
        storedProviders[0]["disabledThinkingOverride"] = "lowEffort"
        root["providers"] = storedProviders

        let decoded = try JSONDecoder().decode(
            AppConfiguration.self, from: JSONSerialization.data(withJSONObject: root)
        )
        let reencoded = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
        )
        let savedProviders = try #require(reencoded["providers"] as? [[String: Any]])
        #expect(savedProviders as NSArray == storedProviders as NSArray)
    }

    @Test(
        "The optional thinking override round-trips through storage",
        arguments: [
            ProviderDisabledThinkingOverride.lowEffort,
            ProviderDisabledThinkingOverride.passthrough,
        ])
    func storageRoundTrip(override: ProviderDisabledThinkingOverride) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = AppConfiguration(providers: [
            Provider(
                name: "example",
                baseURL: "https://example.com",
                authMode: .none,
                disabledThinkingOverride: override
            )
        ])
        let store = ConfigurationStore(
            fileURL: directory.appending(path: "config.json"),
            backupDirectory: directory.appending(path: "backups")
        )

        try store.save(configuration)

        #expect(try store.load() == configuration)
        let provider = try #require(configuration.providers.first)
        #expect(try JSONDecoder().decode(Provider.self, from: JSONEncoder().encode(provider)) == provider)
    }

    @Test(
        "Legacy and null provider settings default to low effort",
        arguments: [1, 7, 8], [false, true])
    func legacyDefaultsToLowEffort(version: Int, explicitNull: Bool) throws {
        let field = explicitNull ? #", "disabledThinkingOverride":null"# : ""
        let json = #"""
            {"version":\#(version),"providers":[{
              "id":"057265e6-9c83-4f9d-92a4-93986f1e30e5",
              "name":"example", "baseURL":"https://example.com", "authMode":"none",
              "models":[], "status":"ready", "maximumParallelRequests":4\#(field)
            }],"mappings":{},"autoMode":false,"connected":false}
            """#

        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: Data(json.utf8))

        #expect(
            try #require(decoded.providers.first).disabledThinkingOverride
                == ProviderDisabledThinkingOverride.lowEffort
        )
    }

    @Test("A persisted provider carrying a retired namespace probe still decodes")
    func decodesLegacyNamespaceProbeKey() throws {
        let json = #"""
            {"version":8,"providers":[{
              "id":"057265e6-9c83-4f9d-92a4-93986f1e30e5",
              "name":"legacy", "baseURL":"https://example.com", "authMode":"none",
              "models":[], "status":"ready", "maximumParallelRequests":4,
              "namespaceProbe":{"verdict":"restored","model":"m","date":7}
            }],"mappings":{},"autoMode":false,"connected":false}
            """#

        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: Data(json.utf8))

        #expect(try #require(decoded.providers.first).name == "legacy")
    }
}
