import Foundation
import Testing

@testable import LittleSwitchCore

// The activation matrix spans both wire origins and the owned-entry cases.
// swiftlint:disable file_length

@Suite("Claude profile transaction")
// The profile transaction's owned-entry cases stay with its fixture.
// swiftlint:disable:next type_body_length
struct ClaudeProfileTests {
    @Test("Live paths resolve the user Application Support directory")
    func livePaths() throws {
        let root = URL(fileURLWithPath: "/tmp/little-switch-claude-live")
        let fileManager = ProfilePathsFileManager(
            home: root.appending(path: "home"),
            applicationSupport: root.appending(path: "support")
        )

        #expect(
            try ClaudeProfilePaths.live(fileManager: fileManager)
                == ClaudeProfilePaths(applicationSupport: root.appending(path: "support"))
        )
        fileManager.applicationSupport = nil
        #expect(throws: ClaudeProfileManager.Error.applicationSupportUnavailable) {
            try ClaudeProfilePaths.live(fileManager: fileManager)
        }
    }

    @Test("Activation purges the legacy marketplaces key from upgraded profiles")
    func activationPurgesLegacyMarketplaces() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        let store = RecordingProfileFileStore(
            backupDirectory: fixture.paths.backupDirectory
        )
        var legacy = try store.readObject(fixture.paths.profile)
        legacy["marketplaces"] = [["source": "github", "repo": "legacy/repo"]]
        try store.writeObject(legacy, to: fixture.paths.profile)
        let manager = ClaudeProfileManager(paths: fixture.paths, fileStore: store)

        try manager.activate(autoMode: true, tlsEnabled: false)

        let profile = try fixture.object(at: fixture.paths.profile)
        #expect(profile["marketplaces"] == nil)
        #expect(
            profile["allowedPluginMarketplaces"] as? [[String: String]]
                == ClaudeProfileManager.defaultMarketplaces
        )
    }

    @Test("Activation preserves unknown data and switches the normal profile last")
    func activationOrderAndPreservation() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        let store = RecordingProfileFileStore(
            backupDirectory: fixture.paths.backupDirectory
        )
        let manager = ClaudeProfileManager(paths: fixture.paths, fileStore: store)

        try manager.activate(autoMode: false, tlsEnabled: true)

        #expect(
            store.writes == [
                fixture.paths.profile,
                fixture.paths.metadata,
                fixture.paths.thirdPartyConfig,
                fixture.paths.normalConfig,
            ])
        let profile = try fixture.object(at: fixture.paths.profile)
        #expect(profile["inferenceProvider"] as? String == "gateway")
        #expect(profile["inferenceGatewayBaseUrl"] as? String == "https://127.0.0.1:11436")
        #expect(profile["deploymentDisplayName"] as? String == "LittleSwitch")
        #expect(profile["unknownProfileField"] as? String == "preserved")
        #expect(profile["autoModeEnabled"] as? Bool == false)
        #expect(profile["allowedPluginMarketplaces"] as? [[String: String]] == ClaudeProfileManager.defaultMarketplaces)
        #expect(profile["marketplaces"] == nil)
        #expect(profile["inferenceModels"] == nil)

        let metadata = try fixture.object(at: fixture.paths.metadata)
        #expect(metadata["appliedId"] as? String == ClaudeProfileIdentity.id)
        let entries = try #require(metadata["entries"] as? [[String: String]])
        #expect(entries.contains(["id": "another-profile", "name": "Other"]))
        #expect(
            entries.contains([
                "id": ClaudeProfileIdentity.id,
                "name": ClaudeProfileIdentity.name,
            ]))
        #expect(try fixture.object(at: fixture.paths.thirdPartyConfig)["deploymentMode"] as? String == "3p")
        #expect(try fixture.object(at: fixture.paths.normalConfig)["deploymentMode"] as? String == "3p")
        #expect(try manager.isActive(autoMode: false))
    }

    @Test("Restore removes only LittleSwitch ownership and preserves unrelated fields")
    func restore() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        let manager = ClaudeProfileManager(paths: fixture.paths)
        try manager.activate(autoMode: true, tlsEnabled: true)

        try manager.restore()

        #expect(try fixture.object(at: fixture.paths.normalConfig)["deploymentMode"] as? String == "1p")
        #expect(try fixture.object(at: fixture.paths.thirdPartyConfig)["deploymentMode"] as? String == "1p")
        let metadata = try fixture.object(at: fixture.paths.metadata)
        #expect(metadata["appliedId"] == nil)
        let entries = try #require(metadata["entries"] as? [[String: String]])
        #expect(entries == [["id": "another-profile", "name": "Other"]])
        let profile = try fixture.object(at: fixture.paths.profile)
        #expect(profile["inferenceProvider"] == nil)
        #expect(profile["inferenceGatewayApiKey"] == nil)
        #expect(profile["unknownProfileField"] as? String == "preserved")
        #expect(profile["chatTabEnabled"] as? Bool == true)
        #expect(profile["disableDeploymentModeChooser"] as? Bool == false)
        #expect(profile["marketplaces"] == nil)
        #expect(profile["allowedPluginMarketplaces"] == nil)
        let active = try manager.isActive(autoMode: true)
        #expect(!active)
    }

    @Test("A partial activation rolls every managed file back byte for byte")
    func activationRollback() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        let original = try fixture.snapshots()
        let store = RecordingProfileFileStore(
            backupDirectory: fixture.paths.backupDirectory,
            failingWrite: 3
        )
        let manager = ClaudeProfileManager(paths: fixture.paths, fileStore: store)

        #expect(throws: RecordingProfileFileStore.Error.injected) {
            try manager.activate(autoMode: true, tlsEnabled: false)
        }
        #expect(try fixture.snapshots() == original)
    }

    @Test("A connected legacy profile remains active during the product rename")
    func legacyIdentityRemainsActive() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        let manager = ClaudeProfileManager(paths: fixture.paths)
        try manager.activate(autoMode: true, tlsEnabled: true)
        var profile = try fixture.object(at: fixture.paths.profile)
        profile["deploymentDisplayName"] = ProductIdentity.Legacy.ModelSwitch.displayName
        profile["inferenceGatewayApiKey"] = ProductIdentity.Legacy.ModelSwitch.gatewayAPIKey
        let profileData = try JSONSerialization.data(
            withJSONObject: profile,
            options: [.prettyPrinted, .sortedKeys]
        )
        try profileData.write(to: fixture.paths.profile)

        #expect(try manager.isActive(autoMode: true))
    }

    @Test("A connected profile from the earliest product era stays active")
    func modelSwitcherIdentityRemainsActive() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        let manager = ClaudeProfileManager(paths: fixture.paths)
        try manager.activate(autoMode: true, tlsEnabled: true)
        var profile = try fixture.object(at: fixture.paths.profile)
        profile["deploymentDisplayName"] = ProductIdentity.Legacy.ModelSwitcher.displayName
        profile["inferenceGatewayApiKey"] = ProductIdentity.Legacy.ModelSwitcher.gatewayAPIKey
        let profileData = try JSONSerialization.data(
            withJSONObject: profile,
            options: [.prettyPrinted, .sortedKeys]
        )
        try profileData.write(to: fixture.paths.profile)

        #expect(try manager.isActive(autoMode: true))
    }

    @Test("Malformed JSON blocks activation before any file changes")
    func malformedInput() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        try Data("[invalid".utf8).write(to: fixture.paths.profile)
        let store = RecordingProfileFileStore(
            backupDirectory: fixture.paths.backupDirectory
        )
        let manager = ClaudeProfileManager(paths: fixture.paths, fileStore: store)

        #expect(throws: (any Swift.Error).self) {
            try manager.activate(autoMode: true, tlsEnabled: false)
        }
        #expect(store.writes.isEmpty)
        #expect(try Data(contentsOf: fixture.paths.profile) == Data("[invalid".utf8))
    }

    @Test("Non-object JSON and invalid model objects are rejected")
    func invalidJSONRootsAndObjects() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        try Data("[]".utf8).write(to: fixture.paths.profile)
        let store = DiskClaudeProfileFileStore(backupDirectory: fixture.paths.backupDirectory)

        #expect(throws: DiskClaudeProfileFileStore.Error.invalidJSON(fixture.paths.profile)) {
            try store.readObject(fixture.paths.profile)
        }
        #expect(throws: DiskClaudeProfileFileStore.Error.invalidJSON(fixture.paths.profile)) {
            try store.writeObject(["invalid": Date()], to: fixture.paths.profile)
        }
    }

    @Test("Removing a profile is successful and idempotent")
    func removingProfile() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        let store = DiskClaudeProfileFileStore(backupDirectory: fixture.paths.backupDirectory)

        try store.restore(nil, to: fixture.paths.profile)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.profile.path))
        try store.restore(nil, to: fixture.paths.profile)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.profile.path))
    }

    @Test("A failed rollback reports rollback failure")
    func rollbackFailure() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        let store = RecordingProfileFileStore(
            backupDirectory: fixture.paths.backupDirectory,
            failingWrite: 2,
            failingRestore: 1
        )
        let manager = ClaudeProfileManager(paths: fixture.paths, fileStore: store)

        #expect(throws: ClaudeProfileManager.Error.rollbackFailed) {
            try manager.activate(autoMode: true, tlsEnabled: false)
        }
    }

    @Test("Activation owns exactly one managed web-search entry")
    func activationWritesManagedWebSearch() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        let store = RecordingProfileFileStore(
            backupDirectory: fixture.paths.backupDirectory
        )
        let manager = ClaudeProfileManager(paths: fixture.paths, fileStore: store)

        try manager.activate(autoMode: true, tlsEnabled: true)

        let profile = try fixture.object(at: fixture.paths.profile)
        let servers = try #require(profile["managedMcpServers"] as? [[String: Any]])
        #expect(servers.count == 1)
        #expect(
            servers[0]["name"] as? String == ClaudeProfileManager.managedWebSearchServerName
        )
        #expect(servers[0]["server"] as? String == "websearch")
        #expect(servers[0]["provider"] as? String == "custom")
        #expect(
            servers[0]["customUrl"] as? String
                == "https://127.0.0.1:11436/api/web-search"
        )
        #expect(
            servers[0]["toolPolicy"] as? [String: String] == ["web_search": "allow"]
        )
    }

    @Test("Activation replaces its stale entry and preserves foreign ones")
    func activationRefreshesManagedWebSearch() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        var profile = try fixture.object(at: fixture.paths.profile)
        profile["managedMcpServers"] = [
            ["name": "Corporate MCP", "server": "remote", "url": "https://corp.example.com"],
            [
                "name": ClaudeProfileManager.managedWebSearchServerName,
                "server": "websearch",
                "provider": "tavily",
                "customUrl": "https://stale.example.com/search",
            ],
        ]
        try fixture.writeJSON(profile, to: fixture.paths.profile)
        let manager = ClaudeProfileManager(paths: fixture.paths)

        try manager.activate(autoMode: true, tlsEnabled: true)

        let updated = try fixture.object(at: fixture.paths.profile)
        let servers = try #require(updated["managedMcpServers"] as? [[String: Any]])
        #expect(servers.count == 2)
        #expect(servers[0]["name"] as? String == "Corporate MCP")
        #expect(
            servers[1]["customUrl"] as? String
                == "https://127.0.0.1:11436/api/web-search"
        )
    }

    @Test("A disabled search configuration leaves the entry unwritten")
    func activationSkipsDisabledWebSearch() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        try fixture.writeJSON(
            ["webSearch": ["provider": "disabled", "resultsLimit": 10, "maximumUses": 3]],
            to: fixture.paths.littleSwitchConfig
        )
        var profile = try fixture.object(at: fixture.paths.profile)
        profile["managedMcpServers"] = [
            [
                "name": ClaudeProfileManager.managedWebSearchServerName,
                "server": "websearch",
                "provider": "custom",
            ]
        ]
        try fixture.writeJSON(profile, to: fixture.paths.profile)
        let manager = ClaudeProfileManager(paths: fixture.paths)

        try manager.activate(autoMode: true, tlsEnabled: true)

        #expect(try fixture.object(at: fixture.paths.profile)["managedMcpServers"] == nil)
    }

    @Test("Without trusted TLS the profile stays on plain http")
    func activationWithoutTLSTaysPlain() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        let manager = ClaudeProfileManager(paths: fixture.paths)

        try manager.activate(autoMode: true, tlsEnabled: false)

        let profile = try fixture.object(at: fixture.paths.profile)
        #expect(
            profile["inferenceGatewayBaseUrl"] as? String
                == ClaudeProfileIdentity.gatewayHTTPBaseURL
        )
        #expect(profile["managedMcpServers"] == nil)
        #expect(try manager.isActive(autoMode: true))
    }

    @Test("Restore drops the owned entry and keeps foreign servers")
    func restoreRemovesManagedWebSearch() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        let manager = ClaudeProfileManager(paths: fixture.paths)
        try manager.activate(autoMode: true, tlsEnabled: true)
        var profile = try fixture.object(at: fixture.paths.profile)
        profile["managedMcpServers"] =
            (profile["managedMcpServers"] as? [Any] ?? [])
            + [["name": "Corporate MCP", "server": "remote"]]
        try fixture.writeJSON(profile, to: fixture.paths.profile)

        try manager.restore()

        let restored = try fixture.object(at: fixture.paths.profile)
        let servers = try #require(restored["managedMcpServers"] as? [[String: Any]])
        #expect(servers.count == 1)
        #expect(servers[0]["name"] as? String == "Corporate MCP")
    }

    @Test("Restore removes the empty managed server key entirely")
    func restoreDropsEmptyManagedWebSearch() throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeInitialFiles()
        let manager = ClaudeProfileManager(paths: fixture.paths)
        try manager.activate(autoMode: true, tlsEnabled: true)

        try manager.restore()

        #expect(try fixture.object(at: fixture.paths.profile)["managedMcpServers"] == nil)
    }
}

private struct ProfileFixture {
    let root: URL
    let paths: ClaudeProfilePaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-profile-\(UUID().uuidString)"
        )
        paths = ClaudeProfilePaths(applicationSupport: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func writeInitialFiles() throws {
        try write(
            [
                "deploymentMode": "1p",
                "normalUnknown": ["keep": true],
            ], to: paths.normalConfig)
        try write(
            [
                "deploymentMode": "1p",
                "thirdPartyUnknown": 42,
            ], to: paths.thirdPartyConfig)
        try write(
            [
                "appliedId": "another-profile",
                "entries": [["id": "another-profile", "name": "Other"]],
                "metadataUnknown": "keep",
            ], to: paths.metadata)
        try write(
            [
                "inferenceModels": ["legacy"],
                "unknownProfileField": "preserved",
            ], to: paths.profile)
    }

    func object(at url: URL) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }

    func writeJSON(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
    }

    func snapshots() throws -> [String: Data] {
        try Dictionary(
            uniqueKeysWithValues: paths.managedFiles.map { url in
                (url.path, try Data(contentsOf: url))
            }
        )
    }

    private func write(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
    }
}

private final class RecordingProfileFileStore: ClaudeProfileFileStore, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case injected
    }

    private let lock = NSLock()
    private let disk: DiskClaudeProfileFileStore
    private let failingWrite: Int?
    private let failingRestore: Int?
    private var writeCount = 0
    private var restoreCount = 0
    private var recordedWrites: [URL] = []

    var writes: [URL] {
        lock.withLock { recordedWrites }
    }

    init(
        backupDirectory: URL,
        failingWrite: Int? = nil,
        failingRestore: Int? = nil
    ) {
        disk = DiskClaudeProfileFileStore(backupDirectory: backupDirectory)
        self.failingWrite = failingWrite
        self.failingRestore = failingRestore
    }

    func snapshot(_ url: URL) throws -> Data? {
        try disk.snapshot(url)
    }

    func readObject(_ url: URL) throws -> [String: Any] {
        try disk.readObject(url)
    }

    func writeObject(_ object: [String: Any], to url: URL) throws {
        let shouldFail = lock.withLock { () -> Bool in
            writeCount += 1
            if writeCount == failingWrite {
                return true
            }
            recordedWrites.append(url)
            return false
        }
        if shouldFail {
            throw Error.injected
        }
        try disk.writeObject(object, to: url)
    }

    func restore(_ data: Data?, to url: URL) throws {
        let shouldFail = lock.withLock { () -> Bool in
            restoreCount += 1
            return restoreCount == failingRestore
        }
        if shouldFail {
            throw Error.injected
        }
        try disk.restore(data, to: url)
    }
}
