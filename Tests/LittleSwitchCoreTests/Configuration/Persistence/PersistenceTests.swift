import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Persistence")
struct PersistenceTests {
    @Test("Configuration round-trips without a secret field")
    func roundTrip() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let providerID = UUID()
        let configuration = AppConfiguration(
            providers: [
                Provider(
                    id: providerID,
                    name: "z.ai",
                    baseURL: "https://api.z.ai/api/coding/paas/v4",
                    authMode: .bearer,
                    models: [DiscoveredModel(id: "glm")],
                    status: .ready,
                    imageInputOverride: .enabled,
                    anthropicBaseURL: "https://api.z.ai/api/anthropic"
                )
            ],
            mappings: [
                "claude-opus-5": ModelMapping(providerID: providerID, modelID: "glm")
            ],
            autoMode: false,
            connected: true,
            claudeCode: ClaudeCodeConfiguration(
                connected: true,
                defaultModel: "claude-opus-5"
            ),
            codex: CodexConfiguration(
                connected: true,
                defaultModel: ModelMapping(providerID: providerID, modelID: "glm"),
                excludedModels: []
            ),
            openCode: OpenCodeConfiguration(
                connected: true,
                defaultModel: ModelMapping(providerID: providerID, modelID: "glm")
            ),
            webSearch: WebSearchConfiguration(
                provider: .firecrawl,
                resultsLimit: 25,
                maximumUses: 4
            )
        )
        let store = ConfigurationStore(
            fileURL: directory.appending(path: "config.json"),
            backupDirectory: directory.appending(path: "backups")
        )

        try store.save(configuration)
        #expect(try store.load() == configuration)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!text.localizedCaseInsensitiveContains("secret"))
        #expect(!text.localizedCaseInsensitiveContains("token"))
        #expect(!text.contains("fc-test-secret"))
    }

    @Test(
        "Provider concurrency limits encode and round-trip at both bounds",
        arguments: [1, 32]
    )
    func providerConcurrencyRoundTrip(maximumParallelRequests: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = AppConfiguration(
            providers: [
                Provider(
                    name: "Provider",
                    baseURL: "https://example.com",
                    authMode: .bearer,
                    maximumParallelRequests: maximumParallelRequests
                )
            ]
        )
        let store = ConfigurationStore(
            fileURL: directory.appending(path: "config.json"),
            backupDirectory: directory.appending(path: "backups")
        )

        try store.save(configuration)

        let data = try Data(contentsOf: store.fileURL)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let providers = try #require(object["providers"] as? [[String: Any]])
        let encodedValue = try #require(
            providers.first?["maximumParallelRequests"] as? Int
        )
        #expect(encodedValue == maximumParallelRequests)
        #expect(try store.load() == configuration)
    }

    @Test("A missing configuration loads defaults")
    func missingFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(
            fileURL: directory.appending(path: "missing.json"),
            backupDirectory: directory.appending(path: "backups")
        )
        #expect(try store.load() == AppConfiguration())
        #expect(AppConfiguration().version == 8)
    }

    @Test("Unsupported and malformed configuration is rejected")
    func invalidConfiguration() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "config.json")
        let store = ConfigurationStore(
            fileURL: file,
            backupDirectory: directory.appending(path: "backups")
        )

        try Data(
            #"""
            {
              "version": 9,
              "providers": [{
                "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                "name": "Future",
                "baseURL": "https://example.com",
                "authMode": "bearer",
                "models": [],
                "status": "idle"
              }],
              "mappings": {},
              "autoMode": true,
              "connected": false
            }
            """#.utf8
        ).write(to: file)
        #expect(throws: ConfigurationStore.Error.unsupportedVersion(9)) {
            try store.load()
        }

        try Data("{".utf8).write(to: file)
        #expect(throws: (any Swift.Error).self) {
            try store.load()
        }
    }

    @Test("Atomic saves retain only five prior versions")
    func boundedBackups() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backupDirectory = directory.appending(path: "backups")
        let store = ConfigurationStore(
            fileURL: directory.appending(path: "config.json"),
            backupDirectory: backupDirectory,
            backupLimit: 5
        )

        for index in 0..<8 {
            try store.save(AppConfiguration(autoMode: index.isMultiple(of: 2)))
        }

        let backups = try FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(backups.count == 5)
        #expect(try store.load().autoMode == false)
    }

    @Test("Atomic writes can replace a file without retaining an automatic backup")
    func disabledBackups() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "settings.json")
        let backupDirectory = directory.appending(path: "backups")
        try Data("before".utf8).write(to: file)
        try FileManager.default.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )
        let explicitBackup = backupDirectory.appending(path: "settings.json.explicit.backup")
        try Data("explicit".utf8).write(to: explicitBackup)

        try AtomicFileWriter.write(
            Data("after".utf8),
            to: file,
            backupDirectory: backupDirectory,
            backupLimit: 0,
            fileManager: CopyRejectingFileManager()
        )

        #expect(try Data(contentsOf: file) == Data("after".utf8))
        #expect(try Data(contentsOf: explicitBackup) == Data("explicit".utf8))
    }
}

extension PersistenceTests {
    @Test("A failed atomic replacement removes its temporary file and preserves prior data")
    func failedAtomicReplacement() throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            try? FileManager.default.removeItem(at: directory)
        }
        let file = directory.appending(path: "config.json")
        let backupDirectory = directory.appending(path: "backups")
        try Data("before".utf8).write(to: file)
        let fileManager = RenameRejectingFileManager(protectedDirectory: directory)

        #expect(throws: POSIXError(.EACCES)) {
            try AtomicFileWriter.write(
                Data("after".utf8),
                to: file,
                backupDirectory: backupDirectory,
                backupLimit: 0,
                fileManager: fileManager
            )
        }

        #expect(try Data(contentsOf: file) == Data("before".utf8))
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(!entries.contains { $0.lastPathComponent.hasSuffix(".tmp") })
    }

    @Test("An unknown rename errno falls back to an IO error")
    func unknownRenameError() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "config.json")
        try Data("before".utf8).write(to: file)

        #expect(throws: POSIXError(.EIO)) {
            try AtomicFileWriter.write(
                Data("after".utf8),
                to: file,
                backupDirectory: directory.appending(path: "backups"),
                backupLimit: 0
            ) { _, _ in Int32.max }
        }
        #expect(try Data(contentsOf: file) == Data("before".utf8))
    }

    @Test("Backup pruning breaks equal creation dates by filename")
    func backupFilenameTieBreaker() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "config.json")
        let backupDirectory = directory.appending(path: "backups")
        try FileManager.default.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )
        try Data("before".utf8).write(to: file)
        let first = backupDirectory.appending(path: "config.json.a.backup")
        let second = backupDirectory.appending(path: "config.json.b.backup")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let creationDate = Date(timeIntervalSince1970: 1_700_000_000)
        for backup in [first, second] {
            try FileManager.default.setAttributes(
                [.creationDate: creationDate],
                ofItemAtPath: backup.path
            )
        }

        try AtomicFileWriter.write(
            Data("after".utf8),
            to: file,
            backupDirectory: backupDirectory,
            backupLimit: 2
        )

        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test("Backup pruning treats missing creation dates as the oldest entries")
    func missingBackupCreationDates() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for missingFirst in [false, true] {
            let root = directory.appending(path: missingFirst ? "missing-first" : "present-first")
            let backupDirectory = root.appending(path: "backups")
            try FileManager.default.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true
            )
            let present = backupDirectory.appending(path: "config.json.present.backup")
            let missing = backupDirectory.appending(path: "config.json.missing.backup")
            try Data("backup".utf8).write(to: present)
            _ = try #require(
                present.resourceValues(forKeys: [.creationDateKey]).creationDate
            )
            let entries = missingFirst ? [missing, present] : [present, missing]
            let fileManager = BackupListingFileManager(entries: entries)
            try AtomicFileWriter.write(
                Data("configuration".utf8),
                to: root.appending(path: "config.json"),
                backupDirectory: backupDirectory,
                backupLimit: 1,
                fileManager: fileManager
            )
            #expect(fileManager.removedItems == [missing])
        }
    }

    @Test("Concurrent atomic rewrites complete without filesystem contention")
    func concurrentAtomicRewrites() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<16 {
                group.addTask {
                    let root = directory.appending(
                        path: "store-\(index)",
                        directoryHint: .isDirectory
                    )
                    let store = ConfigurationStore(
                        fileURL: root.appending(path: "config.json"),
                        backupDirectory: root.appending(path: "backups")
                    )
                    try store.save(AppConfiguration(autoMode: true))
                    try store.save(AppConfiguration(autoMode: false))
                    #expect(try store.load().autoMode == false)
                }
            }
            try await group.waitForAll()
        }
    }

}

private final class CopyRejectingFileManager: FileManager, @unchecked Sendable {
    override func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        throw POSIXError(.EACCES)
    }
}
private final class RenameRejectingFileManager: FileManager, @unchecked Sendable {
    private let protectedDirectory: URL
    init(protectedDirectory: URL) {
        self.protectedDirectory = protectedDirectory
        super.init()
    }

    override func createFile(
        atPath path: String,
        contents data: Data?,
        attributes attr: [FileAttributeKey: Any]? = nil
    ) -> Bool {
        let created = super.createFile(atPath: path, contents: data, attributes: attr)
        if URL(fileURLWithPath: path).lastPathComponent.hasSuffix(".tmp") {
            try? super.setAttributes(
                [.posixPermissions: 0o500],
                ofItemAtPath: protectedDirectory.path
            )
        }
        return created
    }
    override func removeItem(at URL: URL) throws {
        try super.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: protectedDirectory.path
        )
        try super.removeItem(at: URL)
    }
}

private final class BackupListingFileManager: FileManager, @unchecked Sendable {
    private let entries: [URL]
    private(set) var removedItems: [URL] = []
    init(entries: [URL]) {
        self.entries = entries
        super.init()
    }
    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        entries
    }
    override func removeItem(at url: URL) throws {
        removedItems.append(url)
    }
}
