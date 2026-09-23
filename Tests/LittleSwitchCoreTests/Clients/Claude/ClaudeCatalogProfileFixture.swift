import Foundation
import Testing

@testable import LittleSwitchCore

struct ClaudeCatalogProfileFixture {
    let profile: ProfileFixture
    let manager: ClaudeProfileManager
    let store: CatalogProfileFileStore

    static var sonnet: [String: Any] {
        [
            "name": "claude-sonnet-5", "labelOverride": "Sonnet 5 ↦", "anthropicFamilyTier": "sonnet",
            "isFamilyDefault": true, "maxEffort": "max",
        ]
    }

    init(failure: CatalogProfileFileStore.Failure = .none) throws {
        profile = try ProfileFixture()
        try profile.writeInitialFiles()
        try ClaudeProfileManager(paths: profile.paths).activate(autoMode: false, tlsEnabled: false)
        var object = try profile.object(at: profile.paths.profile)
        object["inferenceModels"] = [Self.sonnet]
        object["managedMcpServers"] = [["name": "Corporate", "url": "https://example.com/mcp"]]
        object["foreignMetadata"] = ["null": NSNull(), "settings": [1, 2, 3]]
        try profile.writeJSON(object, to: profile.paths.profile)
        // An invalid persisted configuration must not replace the explicit choices.
        try profile.writeJSON(["invalid": true], to: profile.paths.littleSwitchConfig)
        store = CatalogProfileFileStore(backupDirectory: profile.paths.backupDirectory, failure: failure)
        manager = ClaudeProfileManager(paths: profile.paths, fileStore: store)
    }

    func remove() {
        profile.remove()
    }

    func assertOnlyCatalogChanged(from before: [String: Data]) throws {
        let after = try profile.snapshots()
        for path in profile.paths.managedFiles where path != profile.paths.profile {
            #expect(after[path.path] == before[path.path])
        }
        let originalData = try #require(before[profile.paths.profile.path])
        var original = try #require(JSONSerialization.jsonObject(with: originalData) as? [String: Any])
        var updated = try profile.object(at: profile.paths.profile)
        for key in ["modelDiscoveryEnabled", "inferenceModels"] {
            original.removeValue(forKey: key)
            updated.removeValue(forKey: key)
        }
        #expect(
            try JSONSerialization.data(withJSONObject: updated, options: [.sortedKeys])
                == JSONSerialization.data(withJSONObject: original, options: [.sortedKeys]))
        #expect(try profile.object(at: profile.paths.littleSwitchConfig)["invalid"] as? Bool == true)
    }
}

final class CatalogProfileFileStore: ClaudeProfileFileStore, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case write, restore
    }

    enum Failure: Sendable {
        case none, write, partialWrite, partialWriteAndRestore

        static let writeFailures: [Failure] = [.write, .partialWrite]
    }

    private let disk: DiskClaudeProfileFileStore
    private let failure: Failure
    private let lock = NSLock()
    private var recordedWrites: [URL] = []
    private var recordedRestores: [URL] = []

    var writes: [URL] { lock.withLock { recordedWrites } }
    var restores: [URL] { lock.withLock { recordedRestores } }

    init(backupDirectory: URL, failure: Failure) {
        disk = DiskClaudeProfileFileStore(backupDirectory: backupDirectory)
        self.failure = failure
    }

    func snapshot(_ url: URL) throws -> Data? {
        try disk.snapshot(url)
    }

    func readObject(_ url: URL) throws -> [String: Any] {
        try disk.readObject(url)
    }

    func writeObject(_ object: [String: Any], to url: URL) throws {
        lock.withLock { recordedWrites.append(url) }
        switch failure {
        case .none:
            try disk.writeObject(object, to: url)
        case .write:
            throw Error.write
        case .partialWrite, .partialWriteAndRestore:
            try disk.writeObject(object, to: url)
            throw Error.write
        }
    }

    func restore(_ data: Data?, to url: URL) throws {
        lock.withLock { recordedRestores.append(url) }
        if case .partialWriteAndRestore = failure {
            throw Error.restore
        }
        try disk.restore(data, to: url)
    }
}
