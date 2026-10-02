import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Single-provider configuration")
struct SingleProviderConfigurationTests {
    @Test("Current configuration stores one credential directly on each provider")
    func directCredentials() throws {
        let provider = Provider(
            name: "Separate Claude provider",
            baseURL: "https://synthetic.example",
            authMode: .xAPIKey,
            credentialSource: .script,
            credentialScriptPath: "/synthetic/token.sh",
            credentialRefreshInterval: 900)
        let configuration = AppConfiguration(providers: [provider])
        #expect(configuration.version == 11)
        let data = try JSONEncoder().encode(configuration)
        let encoded = try #require(String(data: data, encoding: .utf8))
        #expect(!encoded.contains("\"accounts\""))
        #expect(!encoded.contains("\"accountStrategy\""))
        #expect(encoded.contains("\"credentialSource\":\"script\""))
        #expect(try JSONDecoder().decode(AppConfiguration.self, from: data) == configuration)
    }

    @Test(
        "Obsolete integration values cannot alter migrated provider settings or image observations",
        arguments: [9, 10, 11], ["openAICompatible", "anthropic", "gemini"])
    func obsoleteIntegration(version: Int, integration: String) throws {
        let provider = Provider(
            id: Self.providerID,
            name: "Separate provider",
            baseURL: "https://synthetic.example/v1",
            authMode: .xAPIKey,
            models: [DiscoveredModel(id: "model")],
            responsesWireOverride: .chatCompletions,
            anthropicBaseURL: "https://synthetic.example/anthropic",
            imageInputObservations: [
                .init(
                    key: .init(
                        providerID: Self.providerID,
                        modelID: "model",
                        wire: .responses,
                        endpoint: "https://synthetic.example/v1/responses"),
                    verdict: .unsupported,
                    source: .providerRejection,
                    observedAt: Date(timeIntervalSince1970: 1))
            ])
        let configuration = AppConfiguration(version: version, providers: [provider])
        var object = try #require(
            JSONSerialization.jsonObject(with: configurationFixtureData(configuration)) as? [String: Any])
        var rows = try #require(object["providers"] as? [[String: Any]])
        rows[0]["integration"] = integration
        object["providers"] = rows
        let decoded = try JSONDecoder().decode(
            AppConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.providers == [provider])
        #expect(decoded.providers.first?.hasSameImageInputIdentity(as: provider) == true)
        let encoded = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        let encodedRows = try #require(encoded["providers"] as? [[String: Any]])
        #expect(encodedRows.first?["integration"] == nil)
    }

    @Test("Experimental primary credentials migrate without changing provider identity", arguments: [false, true])
    func versionTen(script: Bool) throws {
        let credential =
            script
            ? #"{"script":{"authMode":"x-api-key","path":"/synthetic/token.sh","refreshInterval":900}}"#
            : #"{"manual":{"authMode":"x-api-key"}}"#
        let configuration = try JSONDecoder().decode(
            AppConfiguration.self, from: legacy(accounts: [account(credential: credential)]))
        #expect(configuration.version == 11)
        #expect(
            configuration.providers == [
                Provider(
                    id: Self.providerID,
                    name: "Separate provider",
                    baseURL: "https://synthetic.example",
                    authMode: .xAPIKey,
                    credentialSource: script ? .script : .manual,
                    credentialScriptPath: script ? "/synthetic/token.sh" : nil,
                    credentialRefreshInterval: script ? 900 : nil,
                    status: .ready,
                    maximumParallelRequests: 2)
            ])
        #expect(!configuration.connected)
        #expect(configuration.autoMode)
    }

    @Test("Experimental migration keeps provider settings and an exact recovery snapshot")
    func migrationPreservesSettings() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "config.json")
        let backups = directory.appending(path: "backups")
        let provider = Provider(
            id: Self.providerID,
            name: "Separate Claude",
            baseURL: "https://synthetic.example",
            authMode: .xAPIKey,
            models: [DiscoveredModel(id: "model")],
            lastRefresh: Date(timeIntervalSince1970: 10),
            status: .unavailable,
            lastError: "synthetic",
            maximumParallelRequests: 7,
            imageInputOverride: .disabled,
            disabledThinkingOverride: .passthrough,
            responsesWireOverride: .chatCompletions,
            anthropicBaseURL: "https://synthetic.example/anthropic")
        let mapping = ModelMapping(providerID: provider.id, modelID: "model")
        var expected = AppConfiguration(
            version: 10,
            providers: [provider],
            mappings: ["claude-opus-5": mapping],
            autoMode: false,
            connected: true,
            codex: .init(connected: true, defaultModel: mapping),
            modelIndicator: .routed)
        let original = try configurationFixtureData(expected)
        try original.write(to: file)
        let store = ConfigurationStore(fileURL: file, backupDirectory: backups)
        expected.version = 11
        #expect(try store.load() == expected)
        #expect(try Data(contentsOf: file) == original)
        let recovery = try FileManager.default.contentsOfDirectory(
            at: backups.appending(path: "BeforeMigration"), includingPropertiesForKeys: nil)
        #expect(try recovery.map { try Data(contentsOf: $0) } == [original])
        try store.save(expected)
        #expect(try store.load() == expected)
    }

    @Test("Ambiguous experimental accounts are rejected without rewriting configuration", arguments: 0...5)
    func unsafeVersionTen(variant: Int) throws {
        let accounts: [String]
        switch variant {
        case 0: accounts = []
        case 1: accounts = [account(), account(id: UUID())]
        case 2: accounts = [account(enabled: false)]
        case 3: accounts = [account(id: UUID())]
        case 4: accounts = [account(credential: #"{"oauth":{"service":"codex"}}"#)]
        default: accounts = [account(credential: #"{"script":{"authMode":"none"}}"#)]
        }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "config.json")
        let backups = directory.appending(path: "backups")
        let original = legacy(accounts: accounts)
        try original.write(to: file)
        let store = ConfigurationStore(fileURL: file, backupDirectory: backups)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: file) == original)
        #expect(!FileManager.default.fileExists(atPath: backups.path))
    }

    @Test("Provider identities cannot alias the same credential", arguments: [10, 11])
    func duplicateProviderIdentity(version: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "config.json")
        let backups = directory.appending(path: "backups")
        let provider = Provider(name: "One", baseURL: "https://synthetic.example", authMode: .bearer)
        let configuration = AppConfiguration(version: version, providers: [provider, provider])
        let original = try configurationFixtureData(configuration)
        try original.write(to: file)
        let store = ConfigurationStore(fileURL: file, backupDirectory: backups)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(throws: (any Error).self) { try store.save(AppConfiguration(providers: [provider, provider])) }
        #expect(try Data(contentsOf: file) == original)
        #expect(!FileManager.default.fileExists(atPath: backups.path))
    }

    private static let providerID = UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    private func account(
        id: UUID = Self.providerID,
        enabled: Bool = true,
        credential: String = #"{"manual":{"authMode":"x-api-key"}}"#
    ) -> String {
        """
        {"id":"\(id.uuidString)","name":"Primary","isEnabled":\(enabled),"credential":\(credential)}
        """
    }

    private func legacy(accounts: [String]) -> Data {
        Data(
            """
            {"version":10,"providers":[{
              "id":"\(Self.providerID.uuidString)","name":"Separate provider",
              "baseURL":"https://synthetic.example","models":[],"status":"ready","maximumParallelRequests":2,
              "disabledThinkingOverride":"lowEffort",
              "integration":"openAICompatible","accounts":[\(accounts.joined(separator: ","))],
              "accountStrategy":"firstAvailable"
            }],"mappings":{},"autoMode":true,"connected":false}
            """.utf8)
    }
}
