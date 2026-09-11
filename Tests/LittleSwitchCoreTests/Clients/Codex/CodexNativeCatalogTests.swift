import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex native catalog", .serialized)
struct CodexNativeCatalogTests {
    private static let nativeCatalogJSON =
        #"{"models":[{"slug":"gpt-5.6-sol","display_name":"GPT-5.6 Sol","priority":10,"upgrade":"nux","unknown_future":{"x":1}}]}"#

    @Test("Acquisition reads the native cache without starting an authenticated process")
    func cachedCatalogNeverStartsProcess() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let runner = SpyRunner(results: [.success(Data(Self.nativeCatalogJSON.utf8))])

        #expect(fixture.catalog(runner: runner).acquire() == fixture.cacheData)
        #expect(runner.calls.isEmpty)
        #expect(try Data(contentsOf: fixture.root.appending(path: ".codex/auth.json")) == fixture.authData)
    }

    @Test("The bundled fallback runs in an empty private home without credentials")
    func bundledCatalogNeverCopiesAuthentication() throws {
        let fixture = try Fixture.make(withCache: false)
        defer { fixture.remove() }
        setenv("LITTLE_SWITCH_TEST", "kept", 1)
        defer { unsetenv("LITTLE_SWITCH_TEST") }
        let runner = SpyRunner(results: [.success(Data(Self.nativeCatalogJSON.utf8))])

        let data = fixture.catalog(runner: runner).acquire()

        #expect(String(data: try #require(data), encoding: .utf8) == Self.nativeCatalogJSON)
        let call = try #require(runner.calls.first)
        #expect(call.arguments == ["debug", "models", "--bundled"])
        #expect(call.codexHome == call.workingDirectory)
        #expect(!call.hasAPIKey)
        #expect(call.inheritedTestValue == "kept")
        let scratch = try #require(call.workingDirectory)
        let seeded = try #require(runner.scratchSnapshots.first)
        #expect(scratch.isEmpty == false)
        #expect(seeded.isEmpty)
        #expect(runner.scratchPOSIXPermissions.first == 0o700)
        #expect(!FileManager.default.fileExists(atPath: scratch))
        #expect(try Data(contentsOf: fixture.root.appending(path: ".codex/auth.json")) == fixture.authData)
    }

    @Test("Acquisition falls back to the cached native models without a binary")
    func fallsBackToCache() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let runner = SpyRunner(results: [])

        let data = fixture.catalog(runner: runner, executableExists: false).acquire()

        #expect(data == fixture.cacheData)
        #expect(runner.calls.isEmpty)
    }

    @Test("Acquisition falls back to the bundled probe when the cache is missing")
    func fallsBackToBundled() throws {
        let fixture = try Fixture.make(withCache: false)
        defer { fixture.remove() }
        let runner = SpyRunner(results: [.success(Data(Self.nativeCatalogJSON.utf8))])

        let data = fixture.catalog(runner: runner).acquire()

        #expect(String(data: try #require(data), encoding: .utf8) == Self.nativeCatalogJSON)
        #expect(runner.calls.count == 1)
        #expect(try #require(runner.calls.last).arguments == ["debug", "models", "--bundled"])
    }

    @Test("Total acquisition failure degrades to no native models")
    func degradesToEmpty() throws {
        let fixture = try Fixture.make(withCache: false)
        defer { fixture.remove() }
        let runner = SpyRunner(results: [.failure(.notFound)])

        #expect(fixture.catalog(runner: runner).acquire() == nil)
        let scratch = try #require(runner.calls.first?.workingDirectory)
        #expect(!FileManager.default.fileExists(atPath: scratch))
    }

    @Test("Invalid bundled output is rejected and the scratch home is removed")
    func rejectsInvalidBundledCatalog() throws {
        let fixture = try Fixture.make(withCache: false)
        defer { fixture.remove() }
        let runner = SpyRunner(results: [.success(Data(#"{"models":null}"#.utf8))])

        #expect(fixture.catalog(runner: runner).acquire() == nil)
        let scratch = try #require(runner.calls.first?.workingDirectory)
        #expect(!FileManager.default.fileExists(atPath: scratch))
    }

    @Test("An invalid cache falls back to the bundled catalog")
    func invalidCacheFallsBackToBundled() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try Data("not-json".utf8).write(to: fixture.cache)
        let runner = SpyRunner(results: [.success(Data(Self.nativeCatalogJSON.utf8))])

        #expect(fixture.catalog(runner: runner).acquire() == Data(Self.nativeCatalogJSON.utf8))
        #expect(try #require(runner.calls.first).arguments == ["debug", "models", "--bundled"])
    }

    @Test("An invalid cache is discarded instead of merged")
    func invalidCacheIsDiscarded() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        try Data("not-json".utf8).write(to: fixture.cache)

        #expect(fixture.catalog(runner: SpyRunner(results: []), executableExists: false).acquire() == nil)
    }

    @Test("The default locator reports no executable when PATH has no codex")
    func defaultLocatorReturnsNilWithoutExecutable() throws {
        let fixture = try Fixture.make(withCache: false)
        defer { fixture.remove() }
        let originalPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", fixture.root.path, 1)
        defer { setenv("PATH", originalPath, 1) }

        #expect(
            CodexNativeCatalog(
                configDirectory: fixture.root.appending(path: ".codex"),
                runner: SpyRunner(results: [])
            ).acquire() == nil
        )
    }

    @Test("The default locator falls back to the system search path")
    func defaultLocatorFallsBackToSystemPath() throws {
        let fixture = try Fixture.make(withCache: false)
        defer { fixture.remove() }
        let originalPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        unsetenv("PATH")
        defer { setenv("PATH", originalPath, 1) }

        #expect(
            CodexNativeCatalog(
                configDirectory: fixture.root.appending(path: ".codex"),
                runner: SpyRunner(results: [])
            ).acquire() == nil
        )
    }

    @Test("The default locator selects an executable Codex from PATH")
    func defaultLocatorFindsExecutable() throws {
        let fixture = try Fixture.make(withCache: false)
        defer { fixture.remove() }
        let executable = fixture.root.appending(path: "codex")
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let originalPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", fixture.root.path, 1)
        defer { setenv("PATH", originalPath, 1) }
        let runner = SpyRunner(results: [.success(Data(Self.nativeCatalogJSON.utf8))])

        let data = CodexNativeCatalog(
            configDirectory: fixture.root.appending(path: ".codex"),
            runner: runner
        ).acquire()

        #expect(data == Data(Self.nativeCatalogJSON.utf8))
    }

    @Test("The combined catalog keeps LittleSwitch first and marks native models ChatGPT-only")
    func combinesCatalogs() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let native = Data(
            #"""
            {"models":[
              {"slug":"gpt-5.6-sol","display_name":"GPT-5.6 Sol","priority":10,"upgrade":"nux","unknown_future":{"x":1}},
              {"slug":"local/qwen","display_name":"collision"},
              {"slug":"codex-auto-review","display_name":"native review"}
            ]}
            """#.utf8
        )

        let combined = try CodexCatalog.encode(
            providers: fixture.providers,
            configuration: fixture.configuration,
            nativeCatalogData: native
        )
        let root = try #require(
            JSONSerialization.jsonObject(with: combined) as? [String: Any]
        )
        let models = try #require(root["models"] as? [[String: Any]])
        let slugs = try models.map { entry in
            try #require(entry["slug"] as? String)
        }
        #expect(slugs == ["local/qwen", "gpt-5.6-sol", "codex-auto-review"])
        // Codex sorts the picker by priority with a stable sort, so the
        // merged file must already be in display order: priorities match
        // positions and native entries never interleave with managed ones.
        let priorities = try models.map { entry in
            try #require(entry["priority"] as? Int)
        }
        #expect(priorities == Array(priorities.indices))
        let nativeEntry = try #require(models.first { ($0["slug"] as? String) == "gpt-5.6-sol" })
        #expect(nativeEntry["supported_in_api"] as? Bool == false)
        #expect(nativeEntry["display_name"] as? String == "GPT-5.6 Sol")
        #expect((nativeEntry["unknown_future"] as? [String: Any])?["x"] as? Int == 1)
        let managedEntry = try #require(models.first { ($0["slug"] as? String) == "local/qwen" })
        #expect(managedEntry["supported_in_api"] as? Bool == true)
    }

    @Test("Native entries without a usable slug are ignored")
    func ignoresUnusableNativeSlugs() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let native = Data(
            #"{"models":[{"display_name":"No slug"},{"slug":" "},{"slug":"native/gpt"}]}"#.utf8
        )

        let combined = try CodexCatalog.encode(
            providers: fixture.providers,
            configuration: fixture.configuration,
            nativeCatalogData: native
        )
        let root = try #require(JSONSerialization.jsonObject(with: combined) as? [String: Any])
        let slugs = try #require(root["models"] as? [[String: Any]]).map {
            try #require($0["slug"] as? String)
        }

        #expect(slugs == ["local/qwen", "native/gpt", "codex-auto-review"])
    }
}

extension CodexNativeCatalogTests {
    fileprivate struct Fixture {
        enum RunnerError: Swift.Error {
            case notFound
        }

        struct Call {
            let arguments: [String]
            let codexHome: String?
            let hasAPIKey: Bool
            let inheritedTestValue: String?
            let workingDirectory: String?
        }

        let root: URL
        let authData: Data
        let cacheData: Data

        var cache: URL {
            root.appending(path: ".codex/models_cache.json")
        }

        static func make(withCache: Bool = true) throws -> Self {
            let root = FileManager.default.temporaryDirectory.appending(
                path: "little-switch-codex-native-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(
                at: root.appending(path: ".codex"),
                withIntermediateDirectories: true
            )
            let authData = Data(#"{"OPENAI_API_KEY":"session-token"}"#.utf8)
            try authData.write(to: root.appending(path: ".codex/auth.json"))
            var cacheData = Data()
            if withCache {
                cacheData = Data(#"{"models":[{"slug":"cached"}]}"#.utf8)
                try cacheData.write(to: root.appending(path: ".codex/models_cache.json"))
            }
            return Self(root: root, authData: authData, cacheData: cacheData)
        }

        func catalog(
            runner: SpyRunner,
            executableExists: Bool = true
        ) -> CodexNativeCatalog {
            CodexNativeCatalog(
                configDirectory: root.appending(path: ".codex"),
                runner: runner
            ) {
                executableExists ? "/usr/local/bin/codex" : nil
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    fileprivate final class SpyRunner: CodexProcessRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var results: [Result<Data, Fixture.RunnerError>]
        private(set) var calls: [Fixture.Call] = []
        private(set) var scratchSnapshots: [[String: Data]] = []
        private(set) var scratchPOSIXPermissions: [Int?] = []

        init(results: [Result<Data, Fixture.RunnerError>]) {
            self.results = results
        }

        func run(
            executablePath: String,
            arguments: [String],
            environment: [String: String],
            workingDirectory: String?
        ) throws -> Data {
            lock.withLock {
                calls.append(
                    Fixture.Call(
                        arguments: arguments,
                        codexHome: environment["CODEX_HOME"],
                        hasAPIKey: environment["OPENAI_API_KEY"] != nil || environment["CODEX_API_KEY"] != nil,
                        inheritedTestValue: environment["LITTLE_SWITCH_TEST"],
                        workingDirectory: workingDirectory
                    )
                )
            }
            var seeded: [String: Data] = [:]
            if let workingDirectory {
                for name in ["auth.json", "models_cache.json"] {
                    if let data = try? Data(
                        contentsOf: URL(fileURLWithPath: workingDirectory).appending(path: name)
                    ) {
                        seeded[name] = data
                    }
                }
            }
            lock.withLock { scratchSnapshots.append(seeded) }
            let permissions = workingDirectory.flatMap {
                try? FileManager.default.attributesOfItem(atPath: $0)[.posixPermissions] as? Int
            }
            lock.withLock { scratchPOSIXPermissions.append(permissions) }
            guard !results.isEmpty else {
                throw Fixture.RunnerError.notFound
            }
            switch results.removeFirst() {
            case .success(let data):
                return data
            case .failure(let error):
                throw error
            }
        }
    }
}
