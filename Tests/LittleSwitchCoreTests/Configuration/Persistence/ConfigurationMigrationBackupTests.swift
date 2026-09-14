import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Configuration migration recovery")
struct ConfigurationMigrationBackupTests {
    @Test("Every legacy format retains its original bytes outside rotating backups", arguments: 1...7)
    func retainsOriginal(version: Int) throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let original = legacyData(version: version)
        try original.write(to: fixture.store.fileURL)

        var configuration = try fixture.store.load()
        #expect(configuration.version == 8)
        #expect(try Data(contentsOf: fixture.store.fileURL) == original)
        for index in 0..<12 {
            configuration.autoMode = index.isMultiple(of: 2)
            try fixture.store.save(configuration)
        }

        #expect(try backupContents(fixture) == [original])
        let rotating = try FileManager.default.contentsOfDirectory(
            at: fixture.store.backupDirectory, includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "backup" }
        #expect(rotating.count == 5)
        #expect(try fixture.store.load() == configuration)
    }

    @Test("Repeated reads preserve one backup and distinct legacy snapshots retain independent restore points")
    func preservesSnapshots() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let original = legacyData(version: 7)
        try original.write(to: fixture.store.fileURL)
        _ = try fixture.store.load()
        let backup = try #require(backupFiles(fixture).first)
        let historicalDate = Date(timeIntervalSince1970: 123)
        try FileManager.default.setAttributes([.modificationDate: historicalDate], ofItemAtPath: backup.path)
        #expect(
            try FileManager.default.attributesOfItem(atPath: backup.path)[.modificationDate] as? Date == historicalDate)
        _ = try fixture.store.load()
        #expect(try backupContents(fixture) == [original])
        #expect(
            try FileManager.default.attributesOfItem(atPath: backup.path)[.modificationDate] as? Date == historicalDate)

        let changed = legacyData(version: 7, autoMode: false)
        try changed.write(to: fixture.store.fileURL)
        _ = try fixture.store.load()
        #expect(Set(try backupContents(fixture)) == Set([original, changed]))
        #expect(try Data(contentsOf: backup) == original)
    }

    @Test("Backup failure stops migration and leaves the source untouched")
    func backupFailure() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let original = legacyData(version: 7)
        try original.write(to: fixture.store.fileURL)
        try FileManager.default.createDirectory(at: fixture.store.backupDirectory, withIntermediateDirectories: true)
        try Data("blocked directory".utf8).write(to: fixture.protected)

        #expect(throws: (any Error).self) { try fixture.store.load() }
        #expect(try Data(contentsOf: fixture.store.fileURL) == original)
        #expect(try Data(contentsOf: fixture.protected) == Data("blocked directory".utf8))
    }

    @Test("A corrupted protected backup is rejected without overwriting either file")
    func corruptedBackup() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let original = legacyData(version: 7)
        try original.write(to: fixture.store.fileURL)
        _ = try fixture.store.load()
        let backup = try #require(backupFiles(fixture).first)
        let corrupted = Data("damaged backup".utf8)
        try corrupted.write(to: backup)

        #expect(throws: (any Error).self) { try fixture.store.load() }
        #expect(try Data(contentsOf: fixture.store.fileURL) == original)
        #expect(try Data(contentsOf: backup) == corrupted)
    }

    @Test("Missing and current configurations do not create migration artifacts", arguments: [false, true])
    func noMigration(currentFile: Bool) throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        if currentFile {
            try legacyData(version: 8).write(to: fixture.store.fileURL)
        }

        #expect(try fixture.store.load() == AppConfiguration())
        #expect(!FileManager.default.fileExists(atPath: fixture.protected.path))
    }

    @Test(
        "Invalid and unsupported sources never establish a recovery snapshot",
        arguments: [Data("invalid".utf8), Data(#"{"version":7}"#.utf8), Data(#"{"version":9}"#.utf8)]
    )
    func invalidSource(original: Data) throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try original.write(to: fixture.store.fileURL)

        #expect(throws: (any Error).self) { try fixture.store.load() }
        #expect(try Data(contentsOf: fixture.store.fileURL) == original)
        #expect(!FileManager.default.fileExists(atPath: fixture.protected.path))
    }

    @Test("Concurrent readers install one complete recovery snapshot")
    func concurrentReaders() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let original = legacyData(version: 7)
        try original.write(to: fixture.store.fileURL)
        let configurations = try await withThrowingTaskGroup(of: AppConfiguration.self) { group in
            for _ in 0..<16 {
                group.addTask { try fixture.store.load() }
            }
            var values: [AppConfiguration] = []
            for try await value in group { values.append(value) }
            return values
        }

        #expect(configurations == Array(repeating: AppConfiguration(), count: 16))
        #expect(try backupContents(fixture) == [original])
        #expect(try Data(contentsOf: fixture.store.fileURL) == original)
    }

    private struct Fixture: Sendable {
        let root: URL
        let store: ConfigurationStore
        var protected: URL { store.backupDirectory.appending(path: "BeforeMigration") }
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Fixture(
            root: root,
            store: ConfigurationStore(
                fileURL: root.appending(path: "config.json"), backupDirectory: root.appending(path: "backups"))
        )
    }

    private func legacyData(version: Int, autoMode: Bool = true) -> Data {
        Data(
            """
            {
              "version": \(version),
              "providers": [],
              "mappings": {},
              "autoMode": \(autoMode),
              "connected": false
            }

            """.utf8
        )
    }

    private func backupFiles(_ fixture: Fixture) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: fixture.protected.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: fixture.protected, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func backupContents(_ fixture: Fixture) throws -> [Data] {
        try backupFiles(fixture).map { try Data(contentsOf: $0) }
    }
}
