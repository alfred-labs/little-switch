import CryptoKit
import Foundation

/// Keeps the exact legacy representation outside the rolling configuration backups.
/// Content-addressed names retain distinct restore points without duplicating a read.
enum ConfigurationMigrationBackup {
    static func preserve(
        _ data: Data,
        version: Int,
        fileName: String,
        backupDirectory: URL,
        install: @Sendable (URL, URL) throws -> Void = installFile,
        synchronize: @Sendable (URL) throws -> Void = {
            try ConfigurationMigrationBackupSync.synchronize($0)
        }
    ) throws {
        let manager = FileManager.default
        // Resolve aliases such as /var before appending the directory this
        // operation owns; BeforeMigration itself must never be followed.
        let directory = backupDirectory.resolvingSymlinksInPath()
            .appending(path: "BeforeMigration", directoryHint: .isDirectory)
        let existingType = (try? manager.attributesOfItem(atPath: directory.path))?[.type] as? FileAttributeType
        if existingType == .typeSymbolicLink {
            throw CocoaError(.fileReadCorruptFile)
        }
        try manager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try setPrivatePermissions(0o700, at: directory, requiring: .typeDirectory)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let destination = directory.appending(path: "\(fileName).v\(version).\(digest).json")
        if !manager.fileExists(atPath: destination.path) {
            try stageAndInstall(data, destination: destination, directory: directory, install: install)
        }
        try setPrivatePermissions(0o600, at: destination, requiring: .typeRegular)
        try validate(data, at: destination)
        // All callers, including readers that find a competing installation,
        // wait for durable naming and permissions before migration can return.
        try synchronize(destination)
    }

    private static func stageAndInstall(
        _ data: Data,
        destination: URL,
        directory: URL,
        install: @Sendable (URL, URL) throws -> Void
    ) throws {
        let manager = FileManager.default
        let staging = directory.appending(path: ".\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: staging) }
        // The existing writer synchronizes complete bytes before making the staging file visible.
        try AtomicFileWriter.write(data, to: staging, backupDirectory: directory, backupLimit: 0)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
        do {
            // A hard link installs the synchronized file atomically without replacing another reader's copy.
            try install(staging, destination)
        } catch {
            guard manager.fileExists(atPath: destination.path) else { throw error }
        }
    }

    private static func installFile(_ staging: URL, _ destination: URL) throws {
        try FileManager.default.linkItem(at: staging, to: destination)
    }

    private static func validate(_ expected: Data, at destination: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
            try Data(contentsOf: destination) == expected
        else { throw CocoaError(.fileReadCorruptFile) }
    }

    private static func setPrivatePermissions(
        _ permissions: Int,
        at url: URL,
        requiring type: FileAttributeType
    ) throws {
        let manager = FileManager.default
        let attributes = try manager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == type else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }
}
