import Foundation

@testable import LittleSwitchCore

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
            manager: CodexProfileManager(
                paths: paths,
                nativeCatalog: CodexNativeCatalog(
                    configDirectory: paths.config.deletingLastPathComponent()
                ) {
                    nil
                }
            ),
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
