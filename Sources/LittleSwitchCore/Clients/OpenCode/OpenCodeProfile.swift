import Foundation
import LittleSwitchCommon

public struct OpenCodeProfilePaths: Equatable, Sendable {
    public let settings: URL
    public let restoreState: URL
    public let backupDirectory: URL

    public init(settings: URL, restoreState: URL, backupDirectory: URL) {
        self.settings = settings
        self.restoreState = restoreState
        self.backupDirectory = backupDirectory
    }

    public init(homeDirectory: URL, applicationSupport: URL) {
        let supportRoot = applicationSupport.appending(
            path: ProductIdentity.applicationSupportDirectoryName,
            directoryHint: .isDirectory
        )
        settings =
            homeDirectory
            .appending(path: ".config", directoryHint: .isDirectory)
            .appending(path: "opencode", directoryHint: .isDirectory)
            .appending(path: "opencode.json")
        restoreState =
            supportRoot
            .appending(path: "OpenCode", directoryHint: .isDirectory)
            .appending(path: "restore.json")
        backupDirectory =
            supportRoot
            .appending(path: "Backups", directoryHint: .isDirectory)
            .appending(path: "OpenCode", directoryHint: .isDirectory)
    }

    public static func live(fileManager: FileManager = .default) throws -> Self {
        guard
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw OpenCodeProfileManager.Error.applicationSupportUnavailable
        }
        return Self(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            applicationSupport: applicationSupport
        )
    }
}

public enum OpenCodeProfileStatus: Equatable, Sendable {
    case inactive
    case active
    case drifted
}

public protocol OpenCodeProfileManaging: Sendable {
    func activate(managed: OpenCodeManagedSettings) throws
    /// Commits external state inside the profile transaction. The closure must leave
    /// that external state unchanged when it throws.
    func activate(managed: OpenCodeManagedSettings, committing: () throws -> Void) throws
    func restore() throws
    func status(expected: OpenCodeManagedSettings?) throws -> OpenCodeProfileStatus
    func managedSettings() throws -> OpenCodeManagedSettings?
}

public protocol OpenCodeProfileFileStore: Sendable {
    func snapshot(_ url: URL) throws -> Data?
    func permissions(_ url: URL) throws -> Int?
    func write(_ data: Data, to url: URL, permissions: Int) throws
    func remove(_ url: URL) throws
    func contents(of directory: URL) throws -> [URL]
}

public struct DiskOpenCodeProfileFileStore: OpenCodeProfileFileStore {
    public let backupDirectory: URL

    public init(backupDirectory: URL) {
        self.backupDirectory = backupDirectory
    }

    public func snapshot(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    public func permissions(_ url: URL) throws -> Int? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue
    }

    public func write(_ data: Data, to url: URL, permissions: Int) throws {
        try AtomicFileWriter.write(
            data,
            to: url,
            backupDirectory: backupDirectory,
            backupLimit: 0
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
    }

    public func remove(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func contents(of directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }
}

public struct OpenCodeProfileManager: Sendable {
    public enum Error: Swift.Error, Equatable {
        case applicationSupportUnavailable
        case invalidJournal
        case unsupportedJournalVersion(Int)
        case invalidBackupFilename
        case missingBackup
        case rollbackFailed
    }

    private struct Journal: Codable, Equatable, Sendable {
        var version: Int
        var settingsExisted: Bool
        var backupFilename: String?
        var originalPermissions: Int?
        var managed: OpenCodeManagedSettings
    }

    private struct Snapshot {
        var url: URL
        var data: Data?
        var permissions: Int?
    }

    public let paths: OpenCodeProfilePaths
    private let fileStore: any OpenCodeProfileFileStore

    public init(
        paths: OpenCodeProfilePaths,
        fileStore: (any OpenCodeProfileFileStore)? = nil
    ) {
        self.paths = paths
        self.fileStore =
            fileStore
            ?? DiskOpenCodeProfileFileStore(backupDirectory: paths.backupDirectory)
    }

    public func activate(managed: OpenCodeManagedSettings) throws {
        try activate(managed: managed) {}
    }

    public func activate(managed: OpenCodeManagedSettings, committing: () throws -> Void) throws {
        let current = try fileStore.snapshot(paths.settings)
        let currentPermissions = try fileStore.permissions(paths.settings)

        if let journal = try readJournal() {
            try reactivate(
                current: current,
                currentPermissions: currentPermissions,
                journal: journal,
                managed: managed,
                committing: committing
            )
            return
        }

        let activated = try OpenCodeSettingsDocument.activating(current, managed: managed)
        let backupURL = current.map { _ in newBackupURL() }
        let journal = Journal(
            version: 1,
            settingsExisted: current != nil,
            backupFilename: backupURL?.lastPathComponent,
            originalPermissions: currentPermissions,
            managed: managed
        )
        let journalData = try encode(journal)
        var transactionURLs = [paths.restoreState, paths.settings]
        if let backupURL {
            transactionURLs.insert(backupURL, at: 0)
        }

        try transaction(urls: transactionURLs) {
            if let current, let backupURL {
                try fileStore.write(
                    current,
                    to: backupURL,
                    permissions: Self.privatePermissions
                )
            }
            try fileStore.write(
                journalData,
                to: paths.restoreState,
                permissions: Self.privatePermissions
            )
            try fileStore.write(
                activated,
                to: paths.settings,
                permissions: Self.privatePermissions
            )
            try committing()
        }
        try? pruneBackups(protected: backupURL)
    }

    public func restore() throws {
        guard let journal = try readJournal() else {
            return
        }
        let original = try originalData(for: journal)
        let current = try fileStore.snapshot(paths.settings)
        let currentPermissions = try fileStore.permissions(paths.settings)
        let restored: Data?
        if current == (try OpenCodeSettingsDocument.activating(original, managed: journal.managed)) {
            restored = original
        } else {
            restored = try OpenCodeSettingsDocument.restoring(
                current: current,
                original: original,
                managed: journal.managed
            )
        }
        let restoredPermissions =
            journal.originalPermissions
            ?? currentPermissions
            ?? Self.privatePermissions

        try transaction(urls: [paths.settings, paths.restoreState]) {
            if let restored {
                try fileStore.write(
                    restored,
                    to: paths.settings,
                    permissions: restoredPermissions
                )
            } else {
                try fileStore.remove(paths.settings)
            }
            try fileStore.remove(paths.restoreState)
        }
    }

    public func status(expected: OpenCodeManagedSettings?) throws -> OpenCodeProfileStatus {
        guard let journal = try readJournal() else {
            return .inactive
        }
        _ = try originalData(for: journal)
        if let expected, expected.mcp != journal.managed.mcp {
            return .drifted
        }
        let managed = expected ?? journal.managed
        return try OpenCodeSettingsDocument.isManaged(
            fileStore.snapshot(paths.settings),
            managed: managed
        ) ? .active : .drifted
    }

    public func managedSettings() throws -> OpenCodeManagedSettings? {
        guard let journal = try readJournal() else {
            return nil
        }
        _ = try originalData(for: journal)
        return journal.managed
    }

    private func readJournal() throws -> Journal? {
        guard let data = try fileStore.snapshot(paths.restoreState) else {
            return nil
        }
        let journal: Journal
        do {
            journal = try JSONDecoder().decode(Journal.self, from: data)
        } catch {
            throw Error.invalidJournal
        }
        guard journal.version == 1 else {
            throw Error.unsupportedJournalVersion(journal.version)
        }
        if journal.settingsExisted {
            _ = try backupURL(for: journal)
        } else if journal.backupFilename != nil {
            throw Error.invalidBackupFilename
        }
        return journal
    }

    private func originalData(for journal: Journal) throws -> Data? {
        guard journal.settingsExisted else {
            return nil
        }
        let backupURL = try backupURL(for: journal)
        guard let data = try fileStore.snapshot(backupURL) else {
            throw Error.missingBackup
        }
        return data
    }

    private func backupURL(for journal: Journal) throws -> URL {
        guard let filename = journal.backupFilename,
            !filename.isEmpty,
            URL(filePath: filename).lastPathComponent == filename
        else {
            throw Error.invalidBackupFilename
        }
        return paths.backupDirectory.appending(path: filename)
    }

    private func newBackupURL() -> URL {
        let timestamp = String(
            format: "%020.0f",
            Date().timeIntervalSince1970 * 1_000_000
        )
        return paths.backupDirectory.appending(
            path: "opencode.json.\(timestamp).\(UUID().uuidString).backup"
        )
    }

    private func pruneBackups(protected: URL?) throws {
        let backups = try fileStore.contents(of: paths.backupDirectory)
            .filter {
                $0.lastPathComponent.hasPrefix("opencode.json.")
                    && $0.pathExtension == "backup"
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard backups.count > Self.backupLimit else {
            return
        }
        let removable = backups.filter { $0 != protected }
        for backup in removable.prefix(backups.count - Self.backupLimit) {
            try fileStore.remove(backup)
        }
    }

    private func transaction(urls: [URL], operation: () throws -> Void) throws {
        let snapshots = try urls.map { url in
            Snapshot(
                url: url,
                data: try fileStore.snapshot(url),
                permissions: try fileStore.permissions(url)
            )
        }
        do {
            try operation()
        } catch {
            do {
                for snapshot in snapshots.reversed() {
                    if let data = snapshot.data {
                        try fileStore.write(
                            data,
                            to: snapshot.url,
                            permissions: snapshot.permissions ?? Self.privatePermissions
                        )
                    } else {
                        try fileStore.remove(snapshot.url)
                    }
                }
            } catch {
                throw Error.rollbackFailed
            }
            throw error
        }
    }

    private func encode(_ journal: Journal) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(journal)
    }

    private static let privatePermissions = 0o600
    private static let backupLimit = 5
}

extension OpenCodeProfileManager {
    private func reactivate(
        current: Data?,
        currentPermissions: Int?,
        journal existing: Journal,
        managed: OpenCodeManagedSettings,
        committing: () throws -> Void
    ) throws {
        var journal = existing
        let original = try originalData(for: journal)
        let restored = try OpenCodeSettingsDocument.restoring(
            current: current,
            original: original,
            managed: journal.managed
        )
        let activated = try OpenCodeSettingsDocument.activating(restored, managed: managed)
        var recoveryBackup: (url: URL, data: Data)?
        if let mcp = managed.mcp, journal.managed.mcp?.name != mcp.name {
            // Capture the newly owned path after restoring the old name. This retains
            // its original value and any independent edits without claiming other keys.
            let baseline = try OpenCodeSettingsDocument.mcpRecoveryBaseline(original: original, current: restored)
            if let baseline, baseline != original {
                let backupURL = newBackupURL()
                recoveryBackup = (backupURL, baseline)
                journal.settingsExisted = true
                journal.backupFilename = backupURL.lastPathComponent
            }
            journal.originalPermissions = journal.originalPermissions ?? currentPermissions
        }
        journal.managed = managed
        let journalData = try encode(journal)
        var transactionURLs = [paths.restoreState, paths.settings]
        if let recoveryBackup {
            transactionURLs.insert(recoveryBackup.url, at: 0)
        }

        try transaction(urls: transactionURLs) {
            if let recoveryBackup {
                try fileStore.write(recoveryBackup.data, to: recoveryBackup.url, permissions: Self.privatePermissions)
            }
            try fileStore.write(journalData, to: paths.restoreState, permissions: Self.privatePermissions)
            try fileStore.write(activated, to: paths.settings, permissions: Self.privatePermissions)
            try committing()
        }
        if let recoveryBackup {
            try? pruneBackups(protected: recoveryBackup.url)
        }
    }
}

extension OpenCodeProfileManager: OpenCodeProfileManaging {}
