import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

struct OpenCodeProfileFixture {
    let root: URL
    let paths: OpenCodeProfilePaths
    let manager: OpenCodeProfileManager
    let managed: OpenCodeManagedSettings

    static func make() throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-opencode-profile-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = OpenCodeProfilePaths(
            settings: root.appending(path: ".config/opencode/opencode.json"),
            restoreState: root.appending(path: "support/restore.json"),
            backupDirectory: root.appending(path: "backups")
        )
        return Self(
            root: root,
            paths: paths,
            manager: OpenCodeProfileManager(paths: paths),
            managed: openCodeManagedSettings()
        )
    }

    func writeSettings(_ data: Data, permissions: Int) throws {
        try FileManager.default.createDirectory(
            at: paths.settings.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: paths.settings)
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: paths.settings.path
        )
    }

    func backups() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: paths.backupDirectory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: paths.backupDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "backup" }
        .sorted { $0.path < $1.path }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

func openCodeManagedSettings(modelSuffix: String = "first") -> OpenCodeManagedSettings {
    let slug = "little-switch-provider-\(modelSuffix)"
    return OpenCodeManagedSettings(
        model: "little-switch/\(slug)",
        provider: OpenCodeManagedProvider(
            npm: "@ai-sdk/openai",
            name: "LittleSwitch",
            options: OpenCodeManagedProviderOptions(
                baseURL: "http://127.0.0.1:11436/v1",
                apiKey: ProductIdentity.gatewayAPIKey
            ),
            models: [
                slug: OpenCodeManagedModel(
                    name: "Provider / \(modelSuffix)",
                    limit: OpenCodeManagedModelLimit(context: 128_000, output: 8_192)
                )
            ]
        )
    )
}

func openCodeMemoryPaths() -> OpenCodeProfilePaths {
    let root = URL(filePath: "/memory")
    return OpenCodeProfilePaths(
        settings: root.appending(path: ".config/opencode/opencode.json"),
        restoreState: root.appending(path: "support/restore.json"),
        backupDirectory: root.appending(path: "backups")
    )
}

func openCodeJournalData(
    version: Int = 1,
    settingsExisted: Bool = false,
    backupFilename: String?,
    originalPermissions: Int? = nil,
    managed: OpenCodeManagedSettings
) throws -> Data {
    let managedData = try JSONEncoder().encode(managed)
    let managedObject = try JSONSerialization.jsonObject(with: managedData)
    var object: [String: Any] = [
        "version": version,
        "settingsExisted": settingsExisted,
        "managed": managedObject,
    ]
    if let backupFilename {
        object["backupFilename"] = backupFilename
    }
    if let originalPermissions {
        object["originalPermissions"] = originalPermissions
    }
    return try JSONSerialization.data(withJSONObject: object)
}

final class FaultingOpenCodeProfileFileStore: OpenCodeProfileFileStore, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case injected
    }

    struct Entry: Equatable, Sendable {
        var data: Data
        var permissions: Int?
    }

    private let lock = NSLock()
    private var storage: [URL: Entry]
    private var snapshots: [[URL: Entry]] = []
    private var mutation = 0
    private var failingMutations: Set<Int> = []

    init(files: [URL: Entry]) {
        storage = files
    }

    var files: [URL: Entry] {
        lock.withLock { storage }
    }

    var durableSnapshots: [[URL: Entry]] {
        lock.withLock { snapshots }
    }

    func fail(onMutations mutations: Set<Int>) {
        lock.withLock {
            mutation = 0
            failingMutations = mutations
        }
    }

    func snapshot(_ url: URL) throws -> Data? {
        lock.withLock { storage[url]?.data }
    }

    func permissions(_ url: URL) throws -> Int? {
        lock.withLock { storage[url]?.permissions }
    }

    func write(_ data: Data, to url: URL, permissions: Int) throws {
        try mutate {
            storage[url] = Entry(data: data, permissions: permissions)
        }
    }

    func remove(_ url: URL) throws {
        try mutate {
            storage.removeValue(forKey: url)
        }
    }

    func contents(of directory: URL) throws -> [URL] {
        lock.withLock {
            storage.keys.filter {
                $0.deletingLastPathComponent().standardizedFileURL.path
                    == directory.standardizedFileURL.path
            }
        }
    }

    private func mutate(_ body: () -> Void) throws {
        try lock.withLock {
            mutation += 1
            if failingMutations.remove(mutation) != nil {
                throw Error.injected
            }
            body()
            snapshots.append(storage)
        }
    }
}
