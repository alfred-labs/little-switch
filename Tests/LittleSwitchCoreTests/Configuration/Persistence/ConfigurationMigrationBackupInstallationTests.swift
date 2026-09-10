import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Configuration recovery snapshot installation")
struct ConfigurationMigrationInstallTests {
    @Test("A competing reader can install the same complete snapshot", arguments: [false, true])
    func competingInstallation(matching: Bool) throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data(#"{"version":7,"providers":[]}"#.utf8)
        let competing = matching ? original : Data("unexpected contents".utf8)
        let install: @Sendable (URL, URL) throws -> Void = { _, destination in
            try competing.write(to: destination, options: .withoutOverwriting)
            throw CocoaError(.fileWriteFileExists)
        }

        if matching {
            try ConfigurationMigrationBackup.preserve(
                original, version: 7, fileName: "config.json", backupDirectory: root, install: install)
        } else {
            #expect(throws: CocoaError(.fileReadCorruptFile)) {
                try ConfigurationMigrationBackup.preserve(
                    original, version: 7, fileName: "config.json", backupDirectory: root, install: install)
            }
        }
        let files = try protectedFiles(root)
        #expect(files.count == 1)
        #expect(try files.map { try Data(contentsOf: $0) } == [competing])
    }

    @Test("An installation error is propagated and its staging file is removed")
    func installFailure() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let failure = CocoaError(.fileWriteNoPermission)
        let install: @Sendable (URL, URL) throws -> Void = { _, _ in throw failure }

        #expect(throws: failure) {
            try ConfigurationMigrationBackup.preserve(
                Data("snapshot".utf8), version: 7, fileName: "config.json", backupDirectory: root, install: install)
        }
        #expect(try protectedFiles(root).isEmpty)
    }

    @Test("A recovery snapshot is private and never accepts a link back to the mutable source")
    func permissionsAndSymlink() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data(#"{"version":7,"providers":[]}"#.utf8)
        let source = root.appending(path: "original.json")
        try original.write(to: source)
        try ConfigurationMigrationBackup.preserve(
            original, version: 7, fileName: "config.json", backupDirectory: root)
        let backup = try #require(protectedFiles(root).first)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: backup.path)
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: backup.deletingLastPathComponent().path)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        try FileManager.default.removeItem(at: backup)
        try FileManager.default.createSymbolicLink(at: backup, withDestinationURL: source)

        #expect(throws: CocoaError(.fileReadCorruptFile)) {
            try ConfigurationMigrationBackup.preserve(
                original, version: 7, fileName: "config.json", backupDirectory: root)
        }
        #expect(try Data(contentsOf: source) == original)
        #expect(
            try FileManager.default.attributesOfItem(atPath: backup.path)[.type] as? FileAttributeType
                == .typeSymbolicLink)
    }

    @Test("Existing recovery directories and snapshots regain private permissions")
    func existingPermissions() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("snapshot".utf8)
        let protected = root.appending(path: "BeforeMigration")
        try FileManager.default.createDirectory(
            at: protected, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try ConfigurationMigrationBackup.preserve(
            original, version: 7, fileName: "config.json", backupDirectory: root)
        let backup = try #require(protectedFiles(root).first)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: backup.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: protected.path)

        try ConfigurationMigrationBackup.preserve(
            original, version: 7, fileName: "config.json", backupDirectory: root)

        #expect(try permissions(backup) == 0o600)
        #expect(try permissions(protected) == 0o700)
        #expect(try Data(contentsOf: backup) == original)
    }

    @Test("A symbolic recovery directory is rejected before writing to its destination")
    func symbolicDirectory() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "other")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "BeforeMigration"), withDestinationURL: target)

        #expect(throws: CocoaError(.fileReadCorruptFile)) {
            try ConfigurationMigrationBackup.preserve(
                Data("snapshot".utf8), version: 7, fileName: "config.json", backupDirectory: root)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    private func permissions(_ url: URL) throws -> Int? {
        try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func protectedFiles(_ root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root.appending(path: "BeforeMigration"), includingPropertiesForKeys: nil)
    }
}
