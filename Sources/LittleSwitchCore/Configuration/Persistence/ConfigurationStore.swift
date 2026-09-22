import Darwin
import Foundation
import LittleSwitchCommon
import LittleSwitchSearch

public protocol ConfigurationStoring: Sendable {
    func load() throws -> AppConfiguration
    func save(_ configuration: AppConfiguration) throws
}

public struct ConfigurationStore: Sendable {
    public enum Error: Swift.Error, Equatable {
        case unsupportedVersion(Int)
        case invalidMaximumParallelRequests(providerID: UUID, value: Int)
    }

    private struct StoredConfigurationVersion: Decodable {
        var version: Int
    }

    public let fileURL: URL
    public let backupDirectory: URL
    public let backupLimit: Int

    public init(fileURL: URL, backupDirectory: URL, backupLimit: Int = 5) {
        self.fileURL = fileURL
        self.backupDirectory = backupDirectory
        self.backupLimit = backupLimit
    }

    public func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppConfiguration()
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let storedVersion = try decoder.decode(StoredConfigurationVersion.self, from: data).version
        guard (1...9).contains(storedVersion) else {
            throw Error.unsupportedVersion(storedVersion)
        }
        let configuration = try decoder.decode(
            AppConfiguration.self,
            from: data
        )
        if storedVersion != configuration.version {
            try ConfigurationMigrationBackup.preserve(
                data,
                version: storedVersion,
                fileName: fileURL.lastPathComponent,
                backupDirectory: backupDirectory)
        }
        return configuration
    }

    public func save(_ configuration: AppConfiguration) throws {
        for provider in configuration.providers {
            guard Provider.maximumParallelRequestsRange.contains(provider.maximumParallelRequests)
            else {
                throw Error.invalidMaximumParallelRequests(
                    providerID: provider.id,
                    value: provider.maximumParallelRequests
                )
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(configuration)
        try AtomicFileWriter.write(
            data,
            to: fileURL,
            backupDirectory: backupDirectory,
            backupLimit: backupLimit
        )
    }
}

extension ConfigurationStore: ConfigurationStoring {}

enum AtomicFileWriter {
    static func write(
        _ data: Data,
        to destination: URL,
        backupDirectory: URL,
        backupLimit: Int = 5,
        permissions: Int = 0o600,
        fileManager: FileManager = .default,
        renamer: @escaping @Sendable (URL, URL) -> Int32 = { source, destination in
            guard Darwin.rename(source.path, destination.path) == 0 else {
                return errno
            }
            return 0
        }
    ) throws {
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        if backupLimit > 0, fileManager.fileExists(atPath: destination.path) {
            let backup = backupDirectory.appending(
                path: "\(destination.lastPathComponent).\(UUID().uuidString).backup"
            )
            try fileManager.copyItem(at: destination, to: backup)
        }

        let temporary = parent.appending(path: ".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        guard fileManager.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temporary.path])
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            // Restore deliberate user permissions only after the private file
            // is complete, before publishing it. Read-only originals remain writable
            // during preparation, and new data is never written to a public temporary.
            if permissions != 0o600 {
                try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
            }
            try replaceAtomically(temporary, destination: destination, renamer: renamer)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }

        if backupLimit > 0 {
            try? pruneBackups(
                for: destination.lastPathComponent,
                in: backupDirectory,
                keeping: backupLimit,
                fileManager: fileManager
            )
        }
    }

    private static func replaceAtomically(
        _ source: URL,
        destination: URL,
        renamer: @Sendable (URL, URL) -> Int32
    ) throws {
        let errorNumber = renamer(source, destination)
        guard errorNumber == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errorNumber) ?? .EIO)
        }
    }

    private static func pruneBackups(
        for filename: String,
        in directory: URL,
        keeping limit: Int,
        fileManager: FileManager
    ) throws {
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        let backups =
            entries
            .filter { $0.lastPathComponent.hasPrefix("\(filename).") && $0.pathExtension == "backup" }
            .sorted { left, right in
                let leftDate = try? left.resourceValues(forKeys: [.creationDateKey]).creationDate
                let rightDate = try? right.resourceValues(forKeys: [.creationDateKey]).creationDate
                if leftDate == rightDate {
                    return left.lastPathComponent < right.lastPathComponent
                }
                return (leftDate ?? .distantPast) < (rightDate ?? .distantPast)
            }
        guard backups.count > max(0, limit) else {
            return
        }
        for backup in backups.prefix(backups.count - max(0, limit)) {
            try fileManager.removeItem(at: backup)
        }
    }
}
