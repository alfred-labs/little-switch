import Darwin
import Foundation
import Testing

import struct os.OSAllocatedUnfairLock

@testable import LittleSwitchCore

@Suite("Configuration recovery snapshot durability")
struct ConfigurationMigrationDurabilityTests {
    @Test(
        "A private complete snapshot is synchronized after installation and staging cleanup", arguments: [false, true])
    func finalizationOrder(existing: Bool) throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("original snapshot".utf8)
        if existing {
            try ConfigurationMigrationBackup.preserve(
                original, version: 7, fileName: "config.json", backupDirectory: root)
        }
        let calls = OSAllocatedUnfairLock(initialState: [String]())
        try ConfigurationMigrationBackup.preserve(
            original, version: 7, fileName: "config.json", backupDirectory: root
        ) { staging, destination in
            calls.withLock { $0.append("install") }
            try FileManager.default.linkItem(at: staging, to: destination)
        } synchronize: { destination in
            #expect(try Data(contentsOf: destination) == original)
            let manager = FileManager.default
            let attributes = try manager.attributesOfItem(atPath: destination.path)
            let parent = destination.deletingLastPathComponent()
            let parentAttributes = try manager.attributesOfItem(atPath: parent.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            #expect((parentAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
            #expect(try manager.contentsOfDirectory(atPath: parent.path) == [destination.lastPathComponent])
            calls.withLock { $0.append("synchronize") }
        }
        #expect(calls.withLock { $0 } == (existing ? ["synchronize"] : ["install", "synchronize"]))
    }

    @Test("A durability failure is explicit and leaves the source and recovery bytes available for retry")
    func finalizationFailure() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("original snapshot".utf8)
        let source = root.appending(path: "config.json")
        try original.write(to: source)
        let synchronize: @Sendable (URL) throws -> Void = { _ in throw POSIXError(.EIO) }
        #expect(throws: POSIXError(.EIO)) {
            try ConfigurationMigrationBackup.preserve(
                original, version: 7, fileName: "config.json", backupDirectory: root, synchronize: synchronize)
        }
        #expect(try Data(contentsOf: source) == original)
        let files = try FileManager.default.contentsOfDirectory(
            at: root.appending(path: "BeforeMigration"), includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        #expect(try files.map { try Data(contentsOf: $0) } == [original])
        try ConfigurationMigrationBackup.preserve(
            original, version: 7, fileName: "config.json", backupDirectory: root)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test("Every parent directory is synchronized before the final file storage barrier")
    func descriptorOrder() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "snapshot.json")
        try Data("snapshot".utf8).write(to: file)
        let paths = OSAllocatedUnfairLock(initialState: [(String, ConfigurationMigrationBackupSync.Kind)]())
        try ConfigurationMigrationBackupSync.synchronize(file) { descriptor, kind in
            var metadata = stat()
            #expect(Darwin.fstat(descriptor, &metadata) == 0)
            #expect(metadata.st_mode & mode_t(S_IFMT) == mode_t(kind == .directory ? S_IFDIR : S_IFREG))
            var bytes = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            #expect(Darwin.fcntl(descriptor, F_GETPATH, &bytes) == 0)
            let path = String(bytes: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
            #expect(path != nil)
            paths.withLock { $0.append((path ?? "", kind)) }
            return 0
        }
        let observed = paths.withLock { $0 }
        let directories = observed.filter { $0.1 == .directory }.map(\.0)
        #expect(directories.first?.hasSuffix("/\(root.lastPathComponent)") == true)
        #expect(directories.last == "/")
        #expect(Set(directories).count == directories.count)
        for (directory, parent) in zip(directories, directories.dropFirst()) {
            #expect((directory as NSString).deletingLastPathComponent == parent)
        }
        let firstDirectory = try #require(directories.first)
        #expect(observed.last?.1 == .file)
        #expect(observed.last?.0 == "\(firstDirectory)/snapshot.json")
    }

    @Test("The filesystem root is synchronized once before an absent snapshot is reported")
    func rootBoundary() throws {
        let file = URL(filePath: "/littleswitch-absent-\(UUID().uuidString).json")
        let kinds = OSAllocatedUnfairLock(initialState: [ConfigurationMigrationBackupSync.Kind]())
        #expect(throws: POSIXError(.ENOENT)) {
            try ConfigurationMigrationBackupSync.synchronize(file) { _, kind in
                let count = kinds.withLock {
                    $0.append(kind)
                    return $0.count
                }
                return count == 1 ? 0 : ELOOP
            }
        }
        #expect(kinds.withLock { $0 } == [.directory])
    }

    @Test(
        "Known and unrecognized synchronization failures stop before the next durability phase",
        arguments: [false, true], [EIO, Int32.max]
    )
    func descriptorFailure(fileFailure: Bool, errorCode: Int32) throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "snapshot.json")
        try Data("snapshot".utf8).write(to: file)
        let failureKind: ConfigurationMigrationBackupSync.Kind = fileFailure ? .file : .directory
        let kinds = OSAllocatedUnfairLock(initialState: [ConfigurationMigrationBackupSync.Kind]())
        #expect(throws: POSIXError(.EIO)) {
            try ConfigurationMigrationBackupSync.synchronize(file) { _, kind in
                kinds.withLock { $0.append(kind) }
                return kind == failureKind ? errorCode : 0
            }
        }
        #expect(kinds.withLock { $0.last } == failureKind)
        if !fileFailure { #expect(kinds.withLock { $0 } == [.directory]) }
    }

    @Test("A missing directory or file cannot satisfy the durability barrier", arguments: [false, true])
    func missingPath(missingParent: Bool) throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: missingParent ? "missing/snapshot.json" : "snapshot.json")
        #expect(throws: POSIXError(.ENOENT)) {
            try ConfigurationMigrationBackupSync.synchronize(file)
        }
    }

    @Test("Parent directory aliases are resolved while a symbolic snapshot is refused")
    func symbolicPaths() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "actual")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let alias = root.appending(path: "alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        let file = target.appending(path: "snapshot.json")
        let original = Data("snapshot".utf8)
        try original.write(to: file)
        try ConfigurationMigrationBackupSync.synchronize(alias.appending(path: "snapshot.json"))
        let link = target.appending(path: "link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: POSIXError(.ELOOP)) {
            try ConfigurationMigrationBackupSync.synchronize(link)
        }
        #expect(try Data(contentsOf: file) == original)
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
