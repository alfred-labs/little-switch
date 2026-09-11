import Foundation
import os

package protocol CodexProcessRunning: Sendable {
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?
    ) throws -> Data
}

/// Reads Codex's native model catalog so the managed catalog can coexist
/// with it. The probe never mutates the user's Codex home: it runs
/// `codex debug models` inside a scratch CODEX_HOME seeded with copies of
/// the session files, and degrades through the cache and the bundled
/// catalog before giving up (cohabitation is best-effort).
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
        guard let executable = executableLocator() else {
            return cachedCatalog()
        }
        if let data = try? probe(executable: executable, bundled: false, scratch: true) {
            return data
        }
        if let cached = cachedCatalog() {
            return cached
        }
        return try? probe(executable: executable, bundled: true, scratch: false)
    }

    private func probe(executable: String, bundled: Bool, scratch: Bool) throws -> Data {
        var scratchDirectory: URL?
        if scratch {
            let home = FileManager.default.temporaryDirectory.appending(
                path: "little-switch-codex-native-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(
                at: home,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            for name in ["auth.json", "models_cache.json"] {
                let source = configDirectory.appending(path: name)
                guard FileManager.default.fileExists(atPath: source.path) else {
                    continue
                }
                try FileManager.default.copyItem(at: source, to: home.appending(path: name))
            }
            scratchDirectory = home
        }
        defer {
            if let scratchDirectory {
                try? FileManager.default.removeItem(at: scratchDirectory)
            }
        }
        var arguments = ["debug", "models"]
        if bundled {
            arguments.append("--bundled")
        }
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "CODEX_HOME")
        environment.removeValue(forKey: "OPENAI_API_KEY")
        environment.removeValue(forKey: "CODEX_API_KEY")
        if let scratchDirectory {
            environment["CODEX_HOME"] = scratchDirectory.path
        }
        let data = try runner.run(
            executablePath: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: scratchDirectory?.path ?? NSTemporaryDirectory()
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

struct CodexProcessRunner: CodexProcessRunning {
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?
    ) throws -> Data {
        try run(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            timeout: CodexNativeCatalog.probeTimeout
        )
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?,
        timeout: TimeInterval
    ) throws -> Data {
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let output = OSAllocatedUnfairLock(initialState: Data())
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let available = handle.availableData
            if available.isEmpty {
                handle.readabilityHandler = nil
            } else {
                output.withLock { $0.append(available) }
            }
        }
        try process.run()
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = exited.wait(timeout: .now() + 5)
            throw CodexNativeCatalog.Error.timedOut
        }
        guard process.terminationStatus == 0 else {
            throw CodexNativeCatalog.Error.nonZeroExit(process.terminationStatus)
        }
        return output.withLock { $0 }
    }
}
