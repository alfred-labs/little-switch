import Foundation
import Testing

@testable import LittleSwitchCore

struct ClaudeCodeProfileFixture {
    let root: URL
    let paths: ClaudeCodeProfilePaths
    let manager: ClaudeCodeProfileManager
    let managed: ClaudeCodeManagedSettings

    static func make() throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-claude-code-profile-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = ClaudeCodeProfilePaths(
            settings: root.appending(path: ".claude/settings.json"),
            restoreState: root.appending(path: "support/restore.json"),
            backupDirectory: root.appending(path: "backups")
        )
        return Self(
            root: root,
            paths: paths,
            manager: ClaudeCodeProfileManager(paths: paths),
            managed: managedSettings()
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

func managedSettings() -> ClaudeCodeManagedSettings {
    ClaudeCodeManagedSettings(
        model: "claude-sonnet-5",
        environment: [
            "ANTHROPIC_BASE_URL": "http://127.0.0.1:11436",
            "ANTHROPIC_AUTH_TOKEN": ProductIdentity.gatewayAPIKey,
        ]
    )
}

func memoryPaths() -> ClaudeCodeProfilePaths {
    let root = URL(filePath: "/memory")
    return ClaudeCodeProfilePaths(
        settings: root.appending(path: ".claude/settings.json"),
        restoreState: root.appending(path: "support/restore.json"),
        backupDirectory: root.appending(path: "backups")
    )
}

func permissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
}

func jsonObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

func journalData(
    version: Int = 1,
    settingsExisted: Bool = false,
    backupFilename: String?,
    originalPermissions: Int? = nil,
    managed: ClaudeCodeManagedSettings,
    previousManaged: [ClaudeCodeManagedSettings]? = nil
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
    if let previousManaged {
        let previousManagedData = try JSONEncoder().encode(previousManaged)
        object["previousManaged"] = try JSONSerialization.jsonObject(
            with: previousManagedData
        )
    }
    return try JSONSerialization.data(withJSONObject: object)
}

extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}

final class ProfilePathsFileManager: FileManager, @unchecked Sendable {
    let home: URL
    var applicationSupport: URL?

    init(home: URL, applicationSupport: URL?) {
        self.home = home
        self.applicationSupport = applicationSupport
        super.init()
    }

    override var homeDirectoryForCurrentUser: URL {
        home
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        applicationSupport.map { [$0] } ?? []
    }
}

final class FaultingClaudeCodeProfileFileStore: ClaudeCodeProfileFileStore, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case injected
    }

    struct Entry: Equatable, Sendable {
        var data: Data
        var permissions: Int
    }

    private let lock = NSLock()
    private var storage: [URL: Entry]
    private var mutation = 0
    private var failingMutations: Set<Int> = []
    private var hiddenPermissions: Set<URL> = []

    init(files: [URL: Entry]) {
        storage = files
    }

    var files: [URL: Entry] {
        lock.withLock { storage }
    }

    func fail(onMutations mutations: Set<Int>) {
        lock.withLock {
            mutation = 0
            failingMutations = mutations
        }
    }

    func hidePermissions(for urls: Set<URL>) {
        lock.withLock {
            hiddenPermissions = urls
        }
    }

    func snapshot(_ url: URL) throws -> Data? {
        lock.withLock { storage[url]?.data }
    }

    func permissions(_ url: URL) throws -> Int? {
        lock.withLock {
            hiddenPermissions.contains(url) ? nil : storage[url]?.permissions
        }
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
        }
    }
}
