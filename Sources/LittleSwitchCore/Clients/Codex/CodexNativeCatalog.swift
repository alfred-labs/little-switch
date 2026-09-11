import Foundation

package protocol CodexProcessRunning: Sendable {
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?
    ) throws -> Data
}

/// Reads Codex's native model catalog so the managed catalog can coexist
/// with it. The user's cache is read directly, and the only process fallback
/// dumps the binary's bundled catalog in an empty CODEX_HOME. An authenticated
/// probe could rotate OAuth refresh tokens in a disposable copy of auth.json,
/// leaving the original session unusable, so no credentials are ever copied.
package struct CodexNativeCatalog: Sendable {
    package enum Error: Swift.Error, Equatable {
        case timedOut
        case nonZeroExit(Int32)
        case invalidCatalog
    }

    static let probeTimeout: TimeInterval = 30

    private let configDirectory: URL
    private let runner: any CodexProcessRunning
    private let executableLocator: @Sendable () -> String?

    package init(
        configDirectory: URL,
        runner: (any CodexProcessRunning)? = nil,
        executableLocator: (@Sendable () -> String?)? = nil
    ) {
        self.configDirectory = configDirectory
        self.runner = runner ?? Self.defaultRunner
        self.executableLocator = executableLocator ?? Self.defaultExecutableLocator
    }

    /// The raw native catalog data, or nil when every source fails.
    package func acquire() -> Data? {
        if let cached = cachedCatalog() {
            return cached
        }
        guard let executable = executableLocator() else {
            return nil
        }
        return try? probeBundled(executable: executable)
    }

    private func probeBundled(executable: String) throws -> Data {
        let scratchDirectory = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-codex-native-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: scratchDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: scratchDirectory) }
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "OPENAI_API_KEY")
        environment.removeValue(forKey: "CODEX_API_KEY")
        environment["CODEX_HOME"] = scratchDirectory.path
        let data = try runner.run(
            executablePath: executable,
            arguments: ["debug", "models", "--bundled"],
            environment: environment,
            workingDirectory: scratchDirectory.path
        )
        return try Self.validated(data)
    }

    private func cachedCatalog() -> Data? {
        let cacheURL = configDirectory.appending(path: "models_cache.json")
        guard let data = try? Data(contentsOf: cacheURL) else {
            return nil
        }
        return try? Self.validated(data)
    }

    static func validated(_ data: Data) throws -> Data {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["models"] is [[String: Any]]
        else {
            throw Error.invalidCatalog
        }
        return data
    }

    private static let defaultRunner: any CodexProcessRunning = CodexProcessRunner()

    private static let defaultExecutableLocator: @Sendable () -> String? = {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin"
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appending(path: "codex")
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: candidate.path, isDirectory: &isDirectory
            )
            let isExecutable =
                !isDirectory.boolValue
                && FileManager.default.isExecutableFile(atPath: candidate.path)
            if exists, isExecutable {
                return candidate.path
            }
        }
        return nil
    }
}
