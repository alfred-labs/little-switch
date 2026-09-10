import Foundation
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Persistence migrations")
struct ConfigurationMigrationPersistenceTests {
    @Test("Version 1 configuration migrates with integrations disabled")
    func versionOneMigration() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        try Data(
            #"{"version":1,"providers":[],"mappings":{},"autoMode":true,"connected":false}"#.utf8
        ).write(to: fixture.file)

        let migrated = try fixture.store.load()
        #expect(migrated.version == 8)
        #expect(migrated.webSearch == .disabled)
        #expect(migrated.codex == .disconnected)
        #expect(migrated.claudeCode == .disconnected)
        #expect(migrated.openCode == .disconnected)
    }

    @Test("Unknown indicator values and retired route keys migrate leniently")
    func lenientIndicatorAndRetiredRoutes() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let providerID = try #require(
            UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        )
        let json =
            #"{"version":7,"providers":[{"id":"\#(providerID.uuidString)","name":"Local","#
            + #""baseURL":"http://127.0.0.1:11434","authMode":"none","models":[{"id":"qwen"}],"#
            + #""status":"ready","maximumParallelRequests":4}],"#
            + #""mappings":{"claude-sonnet-4-6":{"providerID":"\#(providerID.uuidString)","modelID":"qwen"},"#
            + #""claude-opus-5":{"providerID":"\#(providerID.uuidString)","modelID":"qwen"}},"#
            + #""autoMode":true,"connected":false,"modelIndicator":"bogus"}"#
        try Data(json.utf8).write(to: fixture.file)

        let migrated = try fixture.store.load()

        #expect(migrated.modelIndicator == .mapsTo)
        #expect(Set(migrated.mappings.keys) == ["claude-opus-5"])
    }

    @Test("The retired gateway access key decodes away silently")
    func retiredGatewayAccessKeyDecodesAway() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        // Configurations written by the network-exposure build carry a
        // "gatewayAccessMode" key no field decodes anymore: the gateway is
        // loopback-only unconditionally, so the key must decode away rather
        // than fail the whole configuration.
        let json =
            #"{"version":7,"providers":[],"mappings":{},"#
            + #""gatewayAccessMode":"all-interfaces","#
            + #""autoMode":false,"connected":false}"#
        try Data(json.utf8).write(to: fixture.file)

        let migrated = try fixture.store.load()

        #expect(migrated.providers.isEmpty)
        #expect(migrated.mappings.isEmpty)
        #expect(!migrated.connected)
    }

    @Test("Version 2 configuration migrates with Codex disconnected")
    func versionTwoMigration() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let versionTwoJSON = #"""
            {
              "version": 2,
              "providers": [],
              "mappings": {},
              "autoMode": false,
              "connected": true,
              "webSearch": {
                "provider": "disabled",
                "deployment": "cloud",
                "baseURL": "https://api.firecrawl.dev/v2",
                "resultsLimit": 10,
                "maximumUses": 3
              }
            }
            """#
        try Data(versionTwoJSON.utf8).write(to: fixture.file)

        let migrated = try fixture.store.load()
        #expect(migrated.version == 8)
        #expect(migrated.connected)
        #expect(migrated.codex == .disconnected)
        #expect(migrated.claudeCode == .disconnected)
        #expect(migrated.openCode == .disconnected)
    }

    @Test("Version 3 configuration migrates with Claude Code disconnected")
    func versionThreeMigration() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let versionThree = #"""
            {
              "version": 3,
              "providers": [],
              "mappings": {},
              "autoMode": true,
              "connected": false,
              "codex": { "connected": false, "excludedModels": [] },
              "webSearch": {
                "provider": "disabled",
                "deployment": "cloud",
                "baseURL": "https://api.firecrawl.dev/v2",
                "resultsLimit": 10,
                "maximumUses": 3
              }
            }
            """#
        try Data(versionThree.utf8).write(to: fixture.file)

        let migrated = try fixture.store.load()
        #expect(migrated.version == 8)
        #expect(migrated.claudeCode == .disconnected)
        #expect(migrated.openCode == .disconnected)
    }

    @Test("Version 4 configuration migrates with OpenCode disconnected")
    func versionFourMigration() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let versionFour = #"""
            {
              "version": 4,
              "providers": [],
              "mappings": {},
              "autoMode": true,
              "connected": false,
              "claudeCode": { "connected": false, "contextMode": "standard" },
              "codex": { "connected": false, "excludedModels": [] },
              "webSearch": {
                "provider": "disabled",
                "deployment": "cloud",
                "baseURL": "https://api.firecrawl.dev/v2",
                "resultsLimit": 10,
                "maximumUses": 3
              }
            }
            """#
        try Data(versionFour.utf8).write(to: fixture.file)

        let migrated = try fixture.store.load()
        #expect(migrated.version == 8)
        #expect(migrated.claudeCode == .disconnected)
        #expect(migrated.codex == .disconnected)
        #expect(migrated.openCode == .disconnected)
    }

    @Test("Version 5 configuration migrates with local-only gateway access")
    func versionFiveMigration() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let versionFive = #"""
            {
              "version": 5,
              "providers": [],
              "mappings": {},
              "autoMode": true,
              "connected": false,
              "claudeCode": { "connected": false, "contextMode": "standard" },
              "codex": { "connected": false, "excludedModels": [] },
              "openCode": { "connected": false },
              "webSearch": {
                "provider": "disabled",
                "deployment": "cloud",
                "baseURL": "https://api.firecrawl.dev/v2",
                "resultsLimit": 10,
                "maximumUses": 3
              }
            }
            """#
        try Data(versionFive.utf8).write(to: fixture.file)

        let migrated = try fixture.store.load()
        #expect(migrated.version == 8)
    }

    @Test(
        "Versions 1 through 6 infer the z.ai parallel request recommendation",
        arguments: [1, 2, 3, 4, 5, 6]
    )
    func legacyZAIConcurrencyMigration(storedVersion: Int) throws {
        let migrated = try loadConfiguration(
            version: storedVersion,
            name: "Unrelated provider name",
            baseURL: " HTTPS://API.Z.AI/api/anthropic/ ",
            modelID: "unrelated-model"
        )

        #expect(migrated.version == 8)
        #expect(try #require(migrated.providers.first).maximumParallelRequests == 2)
    }

    @Test(
        "Generic provider hosts infer the default in versions 1 through 6",
        arguments: [1, 2, 3, 4, 5, 6]
    )
    func legacyGenericHostConcurrencyMigration(storedVersion: Int) throws {
        let migrated = try loadConfiguration(
            version: storedVersion,
            name: "Generic",
            baseURL: "https://example.com/v1",
            modelID: "glm"
        )

        #expect(migrated.version == 8)
        #expect(try #require(migrated.providers.first).maximumParallelRequests == 4)
    }

    @Test(
        "Legacy inference ignores invalid URLs and misleading names or models",
        arguments: [
            ("Invalid", "not a URL", "glm"),
            ("z.ai", "https://example.com/v1", "api.z.ai"),
        ]
    )
    func legacyNonHostConcurrencyMigration(
        name: String,
        baseURL: String,
        modelID: String
    ) throws {
        let migrated = try loadConfiguration(
            version: 6,
            name: name,
            baseURL: baseURL,
            modelID: modelID
        )

        #expect(try #require(migrated.providers.first).maximumParallelRequests == 4)
    }

    @Test("Legacy configurations preserve an explicit valid concurrency limit")
    func legacyExplicitConcurrencyMigration() throws {
        let migrated = try loadConfiguration(
            version: 6,
            maximumParallelRequests: "12"
        )

        #expect(migrated.version == 8)
        #expect(try #require(migrated.providers.first).maximumParallelRequests == 12)
    }

    @Test(
        "Legacy configurations reject explicit null and out-of-range concurrency limits",
        arguments: ["null", "0", "33"]
    )
    func legacyInvalidExplicitConcurrency(maximumParallelRequests: String) {
        #expect(throws: DecodingError.self) {
            try loadConfiguration(
                version: 6,
                maximumParallelRequests: maximumParallelRequests
            )
        }
    }

    @Test(
        "Versions 7 and 8 require a non-null in-range concurrency limit",
        arguments: [7, 8], [nil, "null", "0", "33", "\"4\"", "true", "4.5"] as [String?]
    )
    func currentInvalidConcurrency(storedVersion: Int, maximumParallelRequests: String?) {
        #expect(throws: DecodingError.self) {
            try loadConfiguration(
                version: storedVersion,
                maximumParallelRequests: maximumParallelRequests
            )
        }
    }

    private struct Fixture {
        var directory: URL
        var file: URL
        var store: ConfigurationStore
    }

    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appending(path: "config.json")
        return Fixture(
            directory: directory,
            file: file,
            store: ConfigurationStore(
                fileURL: file,
                backupDirectory: directory.appending(path: "backups")
            )
        )
    }

    private func loadConfiguration(
        version: Int,
        name: String = "Provider",
        baseURL: String = "https://example.com",
        modelID: String = "model",
        maximumParallelRequests: String? = nil
    ) throws -> AppConfiguration {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let maximumParallelRequestsField =
            maximumParallelRequests.map {
                ", \"maximumParallelRequests\": \($0)"
            } ?? ""
        let data = Data(
            """
            {
              "version": \(version),
              "providers": [{
                "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                "name": "\(name)",
                "baseURL": "\(baseURL)",
                "authMode": "bearer",
                "models": [{ "id": "\(modelID)" }],
                "status": "idle"\(maximumParallelRequestsField)
              }],
              "mappings": {},
              "autoMode": true,
              "connected": false
            }
            """.utf8
        )
        try data.write(to: fixture.file)
        return try fixture.store.load()
    }
}

extension ConfigurationMigrationPersistenceTests {
    @Test("A missing monitoring section defaults in every supported version", arguments: 1...8)
    func missingMonitoringPreservesExistingSettings(storedVersion: Int) throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let provider = Provider(
            name: "Configured provider",
            baseURL: "https://example.com/v1",
            authMode: .bearer,
            models: [DiscoveredModel(id: "configured-model")],
            maximumParallelRequests: 13
        )
        let mapping = ModelMapping(providerID: provider.id, modelID: "configured-model")
        var expected = AppConfiguration(
            version: storedVersion,
            providers: [provider],
            mappings: ["claude-opus-5": mapping],
            autoMode: false,
            connected: true,
            claudeCode: ClaudeCodeConfiguration(
                connected: true,
                defaultModel: "claude-opus-5",
                contextMode: .extended1M
            ),
            codex: CodexConfiguration(connected: true, defaultModel: mapping, excludedModels: [mapping]),
            openCode: OpenCodeConfiguration(connected: true, defaultModel: mapping),
            webSearch: WebSearchConfiguration(provider: .brave, resultsLimit: 7, maximumUses: 2),
            relaunchTargets: RelaunchTargets(claude: true, codex: true, claudeCode: true, openCode: true),
            modelIndicator: .routed
        )
        let encoded = try JSONEncoder().encode(expected)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "monitoring")
        try JSONSerialization.data(withJSONObject: object).write(to: fixture.file)
        expected.version = 8

        #expect(try fixture.store.load() == expected)
    }

    @Test("Version 8 persists both configured destinations")
    func configuredMonitoringRoundTrip() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let monitoring = MonitoringConfiguration(
            exposeMetrics: false,
            exposeLogs: true,
            metrics: MonitoringDestination(
                enabled: true,
                endpoint: "http://127.0.0.1:9090/api/v1/otlp/v1/metrics",
                authentication: .bearer,
                credentialID: UUID()
            ),
            logs: MonitoringDestination(enabled: true, endpoint: "http://[::1]:3100/otlp/v1/logs"),
            metricIntervalSeconds: 5,
            minimumLogLevel: .warn
        )
        let configuration = AppConfiguration(monitoring: monitoring)

        try fixture.store.save(configuration)

        #expect(try fixture.store.load() == configuration)
    }

    @Test("Unsupported configuration versions fail before decoding fields", arguments: [Int.min, 0, 9, Int.max])
    func unsupportedMonitoringVersion(storedVersion: Int) throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try Data("{\"version\":\(storedVersion)}".utf8).write(to: fixture.file)

        #expect(throws: ConfigurationStore.Error.unsupportedVersion(storedVersion)) {
            try fixture.store.load()
        }
    }

    @Test(
        "Invalid provider concurrency limits do not mutate persisted configuration",
        arguments: [0, 33]
    )
    func rejectsInvalidProviderConcurrencyBeforeWriting(
        maximumParallelRequests: Int
    ) throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let providerID = UUID()
        let validConfiguration = AppConfiguration(
            providers: [
                Provider(
                    id: providerID,
                    name: "Provider",
                    baseURL: "https://example.com",
                    authMode: .bearer
                )
            ]
        )
        try fixture.store.save(validConfiguration)
        let originalData = try Data(contentsOf: fixture.file)
        let backupDirectory = fixture.directory.appending(path: "backups")
        let originalBackups = try FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil
        )
        var invalidConfiguration = validConfiguration
        invalidConfiguration.providers[0].maximumParallelRequests = maximumParallelRequests

        #expect(
            throws: ConfigurationStore.Error.invalidMaximumParallelRequests(
                providerID: providerID,
                value: maximumParallelRequests
            )
        ) {
            try fixture.store.save(invalidConfiguration)
        }

        #expect(try Data(contentsOf: fixture.file) == originalData)
        #expect(try fixture.store.load() == validConfiguration)
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: backupDirectory,
                includingPropertiesForKeys: nil
            ) == originalBackups
        )
    }
}
