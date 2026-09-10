import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex profile")
struct CodexProfileTests {
    @Test("Explicit and live paths use the documented Codex locations")
    func profilePaths() throws {
        let root = URL(fileURLWithPath: "/tmp/little-switch-codex-paths")
        let home = root.appending(path: "home")
        let support = root.appending(path: "support")
        let supportRoot = support.appending(path: "LittleSwitch", directoryHint: .isDirectory)
        let codexRoot = supportRoot.appending(path: "Codex", directoryHint: .isDirectory)
        let expected = CodexProfilePaths(
            config:
                home
                .appending(path: ".codex", directoryHint: .isDirectory)
                .appending(path: "config.toml"),
            catalog: codexRoot.appending(path: "model-catalog.json"),
            restoreState: codexRoot.appending(path: "restore.json"),
            backupDirectory:
                supportRoot
                .appending(path: "Backups", directoryHint: .isDirectory)
                .appending(path: "Codex", directoryHint: .isDirectory)
        )

        #expect(CodexProfilePaths(homeDirectory: home, applicationSupport: support) == expected)
        let fileManager = ProfilePathsFileManager(home: home, applicationSupport: support)
        #expect(try CodexProfilePaths.live(fileManager: fileManager) == expected)
        fileManager.applicationSupport = nil
        #expect(throws: CodexProfileManager.Error.applicationSupportUnavailable) {
            try CodexProfilePaths.live(fileManager: fileManager)
        }
    }

    @Test("Activation writes a healthy catalog and restorable managed config")
    func activationAndRestore() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let original = #"""
            profile = "work"
            model = "gpt-first-party"
            model_provider = "openai"
            model_catalog_json = "/tmp/first-party.json"
            approval_policy = "on-request"

            [model_providers.openai-compatible]
            name = "Existing"
            base_url = "https://example.com/v1"
            wire_api = "responses"
            """#
        try Data(original.utf8).write(to: fixture.paths.config)

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )

        let managed = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        let defaultModel = try #require(
            fixture.configuration.resolvedDefaultModel(in: fixture.providers)
        )
        #expect(
            try CodexTOMLEditor.rootString("model", in: managed)
                == CodexCatalog.slug(for: defaultModel, in: fixture.providers)
        )
        #expect(try CodexTOMLEditor.rootString("model_provider", in: managed) == "little-switch")
        #expect(
            try CodexTOMLEditor.rootString("model_catalog_json", in: managed)
                == fixture.paths.catalog.path
        )
        #expect(FileManager.default.fileExists(atPath: fixture.paths.catalog.path))
        #expect(FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
        #expect(
            try fixture.manager.isActive(
                providers: fixture.providers,
                configuration: fixture.configuration
            )
        )

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(try CodexTOMLEditor.rootString("profile", in: restored) == "work")
        #expect(try CodexTOMLEditor.rootString("model", in: restored) == "gpt-first-party")
        #expect(try CodexTOMLEditor.rootString("model_provider", in: restored) == "openai")
        #expect(
            try CodexTOMLEditor.rootString("model_catalog_json", in: restored)
                == "/tmp/first-party.json"
        )
        #expect(restored.contains("approval_policy = \"on-request\""))
        #expect(restored.contains("[model_providers.openai-compatible]"))
        #expect(!restored.contains("[model_providers.little-switch]"))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.catalog.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
    }

    @Test("Repeated activation preserves the original restore target")
    func repeatedActivation() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        try Data(#"model = "original""#.utf8).write(to: fixture.paths.config)

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )
        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )
        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(try CodexTOMLEditor.rootString("model", in: restored) == "original")
        #expect(try CodexTOMLEditor.rootString("model_provider", in: restored) == nil)
    }

    @Test("Malformed TOML has no file side effects")
    func malformedTOML() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let malformed = Data("model = [".utf8)
        try malformed.write(to: fixture.paths.config)

        #expect(throws: (any Swift.Error).self) {
            try fixture.manager.activate(
                providers: fixture.providers,
                configuration: fixture.configuration
            )
        }

        #expect(try Data(contentsOf: fixture.paths.config) == malformed)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.catalog.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.backupDirectory.path))
    }

    @Test("Restore does not overwrite manually changed root values")
    func manualDrift() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        try Data(#"model_provider = "openai""#.utf8).write(to: fixture.paths.config)
        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )
        var managed = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        managed = managed.replacingOccurrences(
            of: #"model_provider = "little-switch""#,
            with: #"model_provider = "manual""#
        )
        try Data(managed.utf8).write(to: fixture.paths.config)

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(try CodexTOMLEditor.rootString("model_provider", in: restored) == "manual")
        #expect(!restored.contains("[model_providers.little-switch]"))
        #expect(FileManager.default.fileExists(atPath: fixture.paths.catalog.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
    }

    @Test("Restore removes a config that did not exist before activation")
    func missingOriginalConfig() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )
        #expect(FileManager.default.fileExists(atPath: fixture.paths.config.path))

        try fixture.manager.restore()

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.config.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.catalog.path))
    }
}

extension CodexProfileTests {
    @Test("Activation rejects an empty catalog before writing files")
    func emptyCatalog() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }

        #expect(throws: CodexCatalog.Error.empty) {
            try fixture.manager.activate(providers: [], configuration: .disconnected)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.catalog.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
    }

    @Test("Disconnected restore without saved state removes managed files")
    func disconnectedRestore() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.paths.catalog.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("catalog".utf8).write(to: fixture.paths.catalog)
        try Data("state".utf8).write(to: fixture.paths.restoreState)

        try fixture.manager.restore()

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.catalog.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
    }

    @Test("Managed restore without saved state removes managed root values")
    func restoreWithoutSavedState() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let defaultModel = try #require(
            fixture.configuration.resolvedDefaultModel(in: fixture.providers)
        )
        let managed = try CodexTOMLEditor.activating(
            "approval_policy = \"on-request\"",
            model: CodexCatalog.slug(for: defaultModel, in: fixture.providers),
            catalogPath: fixture.paths.catalog.path
        )
        try Data(managed.utf8).write(to: fixture.paths.config)
        try FileManager.default.createDirectory(
            at: fixture.paths.catalog.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("catalog".utf8).write(to: fixture.paths.catalog)

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(restored.contains("approval_policy = \"on-request\""))
        #expect(try CodexTOMLEditor.rootString("model", in: restored) == nil)
        #expect(try CodexTOMLEditor.rootString("model_provider", in: restored) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.catalog.path))
    }

    @Test("Every inactive signature comparison returns false")
    func inactiveSignatures() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        #expect(
            try !fixture.manager.isActive(
                providers: fixture.providers,
                configuration: fixture.configuration
            )
        )
        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )
        let activeText = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        let activeCatalog = try Data(contentsOf: fixture.paths.catalog)
        #expect(
            try !fixture.manager.isActive(
                providers: [],
                configuration: .disconnected
            )
        )
        let defaultModel = try #require(
            fixture.configuration.resolvedDefaultModel(in: fixture.providers)
        )
        let slug = CodexCatalog.slug(for: defaultModel, in: fixture.providers)
        let variants = [
            "profile = \"work\"\n\(activeText)",
            activeText.replacingOccurrences(of: "model = \"\(slug)\"", with: "model = \"stale\""),
            activeText.replacingOccurrences(
                of: "model_provider = \"little-switch\"",
                with: "model_provider = \"openai\""
            ),
            activeText.replacingOccurrences(
                of: "model_catalog_json = \"\(fixture.paths.catalog.path)\"",
                with: "model_catalog_json = \"/tmp/stale.json\""
            ),
            activeText.replacingOccurrences(of: "name = \"LittleSwitch\"", with: "name = \"Stale\""),
            activeText.replacingOccurrences(
                of: "base_url = \"http://127.0.0.1:11436/v1/\"",
                with: "base_url = \"http://127.0.0.1:1/v1/\""
            ),
            activeText.replacingOccurrences(of: "wire_api = \"responses\"", with: "wire_api = \"chat\""),
        ]
        for variant in variants {
            try Data(variant.utf8).write(to: fixture.paths.config)
            #expect(
                try !fixture.manager.isActive(
                    providers: fixture.providers,
                    configuration: fixture.configuration
                )
            )
        }
        try Data(activeText.utf8).write(to: fixture.paths.config)
        try Data("stale catalog".utf8).write(to: fixture.paths.catalog)
        #expect(
            try !fixture.manager.isActive(
                providers: fixture.providers,
                configuration: fixture.configuration
            )
        )
        try activeCatalog.write(to: fixture.paths.catalog)
    }

    @Test("Activation preserves its originating write error after rollback")
    func originatingWriteError() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let config = Data("# prior config\nmodel = \"prior\"\n".utf8)
        let restoreState = Data("prior restore state".utf8)
        let disk = DiskCodexProfileFileStore(backupDirectory: fixture.paths.backupDirectory)
        try disk.write(config, to: fixture.paths.config)
        try disk.write(restoreState, to: fixture.paths.restoreState)
        let store = FaultingCodexProfileFileStore(
            backupDirectory: fixture.paths.backupDirectory,
            failingWrite: 2
        )
        let manager = CodexProfileManager(paths: fixture.paths, fileStore: store)
        #expect(throws: FaultingCodexProfileFileStore.Error.injected) {
            try manager.activate(
                providers: fixture.providers,
                configuration: fixture.configuration
            )
        }
        #expect(try Data(contentsOf: fixture.paths.config) == config)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.catalog.path))
        #expect(try Data(contentsOf: fixture.paths.restoreState) == restoreState)
    }

    @Test("A failed activation rollback reports rollback failure")
    func rollbackFailure() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let store = FaultingCodexProfileFileStore(
            backupDirectory: fixture.paths.backupDirectory,
            failingWrite: 2,
            failingRestore: 1
        )
        let manager = CodexProfileManager(paths: fixture.paths, fileStore: store)

        #expect(throws: CodexProfileManager.Error.rollbackFailed) {
            try manager.activate(
                providers: fixture.providers,
                configuration: fixture.configuration
            )
        }
    }

    @Test("Invalid UTF-8 configuration data is rejected")
    func invalidUTF8() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        try Data([0xFF]).write(to: fixture.paths.config)

        #expect(throws: CodexProfileManager.Error.invalidUTF8(fixture.paths.config)) {
            try fixture.manager.activate(
                providers: fixture.providers,
                configuration: fixture.configuration
            )
        }
    }

    @Test("Disk restore writes exact bytes back to a managed file")
    func diskRestoreData() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let store = DiskCodexProfileFileStore(backupDirectory: fixture.paths.backupDirectory)

        try store.restore(Data("restored".utf8), to: fixture.paths.catalog)

        #expect(try Data(contentsOf: fixture.paths.catalog) == Data("restored".utf8))
    }

    @Test("Permission failures preserve the underlying POSIX error")
    func permissionFailure() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let recorder = PermissionCallRecorder()
        let store = DiskCodexProfileFileStore(
            backupDirectory: fixture.paths.backupDirectory
        ) { permissions, url in
            try recorder.reject(permissions: permissions, url: url)
        }
        #expect(throws: POSIXError(.EACCES)) {
            try store.write(Data("catalog".utf8), to: fixture.paths.catalog)
        }
        #expect(recorder.call?.permissions == 0o600)
        #expect(recorder.call?.url == fixture.paths.catalog)
    }
}

struct CodexProfileFixture {
    let root: URL
    let paths: CodexProfilePaths
    let manager: CodexProfileManager
    let providers: [Provider]
    let configuration: CodexConfiguration

    static func make(maximumParallelRequests: Int = 4) throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-codex-profile-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = CodexProfilePaths(
            config: root.appending(path: ".codex/config.toml"),
            catalog: root.appending(path: "support/model-catalog.json"),
            restoreState: root.appending(path: "support/restore.json"),
            backupDirectory: root.appending(path: "backups")
        )
        try FileManager.default.createDirectory(
            at: paths.config.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let providerID = UUID()
        let mapping = ModelMapping(providerID: providerID, modelID: "qwen")
        return Self(
            root: root,
            paths: paths,
            manager: CodexProfileManager(paths: paths),
            providers: [
                Provider(
                    id: providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none,
                    models: [DiscoveredModel(id: "qwen", detectedContextWindow: 262_144)],
                    maximumParallelRequests: maximumParallelRequests
                )
            ],
            configuration: CodexConfiguration(defaultModel: mapping)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

final class FaultingCodexProfileFileStore: CodexProfileFileStore, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case injected
    }

    private let lock = NSLock()
    private let disk: DiskCodexProfileFileStore
    private let failingWrite: Int?
    private let failingRestore: Int?
    private var writeCount = 0
    private var restoreCount = 0

    init(
        backupDirectory: URL,
        failingWrite: Int? = nil,
        failingRestore: Int? = nil
    ) {
        disk = DiskCodexProfileFileStore(backupDirectory: backupDirectory)
        self.failingWrite = failingWrite
        self.failingRestore = failingRestore
    }

    func snapshot(_ url: URL) throws -> Data? {
        try disk.snapshot(url)
    }

    func write(_ data: Data, to url: URL) throws {
        let shouldFail = lock.withLock { () -> Bool in
            writeCount += 1
            return writeCount == failingWrite
        }
        if shouldFail {
            throw Error.injected
        }
        try disk.write(data, to: url)
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
