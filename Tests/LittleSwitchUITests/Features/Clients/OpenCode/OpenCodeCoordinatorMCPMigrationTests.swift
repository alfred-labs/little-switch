import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("OpenCode coordinator MCP migration")
struct OpenCodeCoordinatorMCPMigrationTests {
    @Test("A connected legacy profile stays pending until Apply installs MCP")
    func legacyApply() async throws {
        let fixture = try await fixture()
        defer { fixture.remove() }

        let initial = await fixture.coordinator.snapshot()
        #expect(initial.openCodeStatus == .needsAttention)
        #expect(initial.hasPendingOpenCodeChanges)

        let applied = try await fixture.coordinator.applyOpenCode()

        #expect(applied.openCodeStatus == .connected)
        #expect(!applied.hasPendingOpenCodeChanges)
        #expect(try fixture.profile.status(expected: fixture.expected) == .active)
        _ = try await fixture.coordinator.disconnectOpenCode()
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.settings.path))
    }

    @Test("A failed migration save restores the legacy signature and existing MCP entry", arguments: [false, true])
    func failedMigrationSave(existingMCP: Bool) async throws {
        let fixture = try await fixture(existingMCP: existingMCP)
        defer { fixture.remove() }
        let before = try profileFiles(fixture)
        let configuration = fixture.store.configuration
        fixture.store.failNextSave()

        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.applyOpenCode()
        }

        #expect(try profileFiles(fixture) == before)
        #expect(fixture.store.configuration == configuration)
        #expect(try fixture.profile.status(expected: fixture.expected) == .drifted)
        #expect(try fixture.profile.status(expected: nil) == .active)
        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.hasPendingOpenCodeChanges)
        #expect(snapshot.openCodeStatus == .needsAttention)
        #expect(snapshot.configuration.openCode.connected)
        #expect(fixture.store.configuration.openCode.connected)
    }

    @Test("External MCP drift remains pending even when the journal signature is current")
    func currentSignatureDrift() async throws {
        let fixture = try await fixture()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.applyOpenCode()
        var current = try object(Data(contentsOf: fixture.paths.settings))
        var servers = try #require(current["mcp"] as? [String: Any])
        var owned = try #require(servers["web"] as? [String: Any])
        owned["enabled"] = false
        servers["web"] = owned
        current["mcp"] = servers
        try JSONSerialization.data(withJSONObject: current).write(to: fixture.paths.settings)

        try await fixture.coordinator.initializeOpenCodeStatus()

        let pending = await fixture.coordinator.snapshot()
        #expect(pending.hasPendingOpenCodeChanges)
        #expect(pending.openCodeStatus == .needsAttention)
        let applied = try await fixture.coordinator.applyOpenCode()
        #expect(!applied.hasPendingOpenCodeChanges)
        #expect(try fixture.profile.status(expected: fixture.expected) == .active)
    }

    @Test("Failed Apply preserves exact external MCP drift, journal, backups and modes", arguments: [false, true])
    func failedApplyPreservesExternalMCP(customServer: Bool) async throws {
        let fixture = try await fixture()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.applyOpenCode()
        var current = try object(Data(contentsOf: fixture.paths.settings))
        var servers = try #require(current["mcp"] as? [String: Any])
        var owned = try #require(servers["web"] as? [String: Any])
        if customServer {
            owned = ["type": "local", "command": ["custom"], "enabled": false]
        } else {
            owned["enabled"] = false
        }
        servers["web"] = owned
        current["mcp"] = servers
        try JSONSerialization.data(withJSONObject: current, options: [.sortedKeys]).write(to: fixture.paths.settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: fixture.paths.settings.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: fixture.paths.restoreState.path)
        try await fixture.coordinator.initializeOpenCodeStatus()
        let before = try profileFiles(fixture)
        let configuration = fixture.store.configuration
        fixture.store.failNextSave()

        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.applyOpenCode()
        }

        #expect(try profileFiles(fixture) == before)
        #expect(fixture.store.configuration == configuration)
        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.configuration == configuration)
        #expect(snapshot.hasPendingOpenCodeChanges)
        #expect(snapshot.openCodeStatus == .needsAttention)
    }

    private struct FileSnapshot: Equatable {
        var data: Data
        var permissions: Int
    }

    private func profileFiles(_ fixture: Fixture) throws -> [URL: FileSnapshot] {
        let backups = try FileManager.default.contentsOfDirectory(
            at: fixture.paths.backupDirectory,
            includingPropertiesForKeys: nil
        )
        return try Dictionary(
            uniqueKeysWithValues: ([fixture.paths.settings, fixture.paths.restoreState] + backups).map { url in
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let permissions = try #require(attributes[.posixPermissions] as? NSNumber).intValue
                return (url, FileSnapshot(data: try Data(contentsOf: url), permissions: permissions))
            })
    }

    private struct Fixture {
        let root: URL
        let paths: OpenCodeProfilePaths
        let profile: OpenCodeProfileManager
        let store: RecordingConfigurationStore
        let coordinator: ApplicationCoordinator
        let expected: OpenCodeManagedSettings

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func fixture(existingMCP: Bool = false) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(path: "little-switch-opencode-mcp-\(UUID())")
        let paths = OpenCodeProfilePaths(
            settings: root.appending(path: "opencode.json"),
            restoreState: root.appending(path: "restore.json"),
            backupDirectory: root.appending(path: "backups")
        )
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "model")],
            status: .ready
        )
        let mapping = ModelMapping(providerID: provider.id, modelID: "model")
        let configuration = AppConfiguration(
            providers: [provider],
            codex: CodexConfiguration(defaultModel: mapping),
            openCode: OpenCodeConfiguration(connected: true, defaultModel: mapping)
        )
        let expected = try OpenCodeManagedSettings.resolve(
            providers: configuration.providers,
            codex: configuration.codex,
            configuration: configuration.openCode
        )
        var legacy = expected
        legacy.mcp = nil
        let profile = OpenCodeProfileManager(paths: paths)
        try profile.activate(managed: legacy)
        if existingMCP {
            var current = try object(Data(contentsOf: paths.settings))
            current["mcp"] = ["web": ["type": "local", "command": ["custom"]]]
            try JSONSerialization.data(withJSONObject: current).write(to: paths.settings)
        }
        let store = RecordingConfigurationStore(configuration: configuration)
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            openCodeProfileManager: profile,
            discoveryTransport: StaticCatalogTransport(catalogBody: #"{"data":[{"id":"model"}]}"#),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
        _ = try await coordinator.start()
        store.clearSaves()
        return Fixture(
            root: root, paths: paths, profile: profile, store: store, coordinator: coordinator, expected: expected
        )
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
