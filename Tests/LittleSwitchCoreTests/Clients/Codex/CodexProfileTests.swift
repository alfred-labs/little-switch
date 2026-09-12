import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex profile")
struct CodexProfileTests {
    @Test("Activation merges the acquired native catalog and status accepts it")
    func activationWithNativeCatalog() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let native = Data(
            #"{"models":[{"slug":"gpt-5.6-sol","display_name":"GPT-5.6 Sol"}]}"#.utf8
        )
        let manager = CodexProfileManager(
            paths: fixture.paths,
            fileStore: nil,
            nativeCatalog: CodexNativeCatalog(
                configDirectory: fixture.paths.config.deletingLastPathComponent(),
                runner: StubNativeRunner(output: native)
            ) {
                "/usr/local/bin/little-switch-test-codex"
            }
        )

        try manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )

        let catalog = try Data(contentsOf: fixture.paths.catalog)
        let root = try #require(JSONSerialization.jsonObject(with: catalog) as? [String: Any])
        let models = try #require(root["models"] as? [[String: Any]])
        let slugs = models.compactMap { $0["slug"] as? String }
        #expect(slugs == ["local/qwen", "gpt-5.6-sol", "little-switch-auto-review"])
        let expected = try CodexManagedProfileSignature.resolve(
            providers: fixture.providers,
            configuration: fixture.configuration
        )
        #expect(
            try manager.status(providers: fixture.providers, configuration: fixture.configuration, expected: expected)
                == .active(expected)
        )

        try manager.restore()
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.config.path))
    }

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
        #expect(try CodexTOMLEditor.rootString("model_provider", in: managed) == nil)
        #expect(
            try CodexTOMLEditor.rootString("openai_base_url", in: managed)
                == "http://127.0.0.1:11436/v1"
        )
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
            of: "openai_base_url = \"http://127.0.0.1:11436/v1\"",
            with: "openai_base_url = \"http://127.0.0.1:1/v1\""
        )
        try Data(managed.utf8).write(to: fixture.paths.config)

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(
            try CodexTOMLEditor.rootString("openai_base_url", in: restored)
                == "http://127.0.0.1:1/v1"
        )
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
                of: "openai_base_url = \"http://127.0.0.1:11436/v1\"",
                with: "openai_base_url = \"http://127.0.0.1:1/v1\""
            ),
            activeText.replacingOccurrences(
                of: "model_catalog_json = \"\(fixture.paths.catalog.path)\"",
                with: "model_catalog_json = \"/tmp/stale.json\""
            ),
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

/// canned `codex debug models` output for native-catalog acquisition tests.
private struct StubNativeRunner: CodexProcessRunning {
    let output: Data

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?
    ) throws -> Data {
        output
    }
}
