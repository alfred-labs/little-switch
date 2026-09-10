import Foundation

public struct ClaudeCodeProfilePaths: Equatable, Sendable {
    public let settings: URL
    public let restoreState: URL
    public let backupDirectory: URL

    public init(
        settings: URL,
        restoreState: URL,
        backupDirectory: URL
    ) {
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
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: "settings.json")
        restoreState =
            supportRoot
            .appending(path: "ClaudeCode", directoryHint: .isDirectory)
            .appending(path: "restore.json")
        backupDirectory =
            supportRoot
            .appending(path: "Backups", directoryHint: .isDirectory)
            .appending(path: "ClaudeCode", directoryHint: .isDirectory)
    }

    public static func live(fileManager: FileManager = .default) throws -> Self {
        guard
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw ClaudeCodeProfileManager.Error.applicationSupportUnavailable
        }
        return Self(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            applicationSupport: applicationSupport
        )
    }
}

public enum ClaudeCodeProfileStatus: Equatable, Sendable {
    case inactive
    case active
    case drifted
}

public protocol ClaudeCodeProfileManaging: Sendable {
    func activate(managed: ClaudeCodeManagedSettings) throws
    func restore() throws
    func status(expected: ClaudeCodeManagedSettings?) throws -> ClaudeCodeProfileStatus
}

public protocol ClaudeCodeProfileFileStore: Sendable {
    func snapshot(_ url: URL) throws -> Data?
    func permissions(_ url: URL) throws -> Int?
    func write(_ data: Data, to url: URL, permissions: Int) throws
    func remove(_ url: URL) throws
    func contents(of directory: URL) throws -> [URL]
}

public struct DiskClaudeCodeProfileFileStore: ClaudeCodeProfileFileStore {
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

public struct ClaudeCodeProfileManager: Sendable {
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
        var managed: ClaudeCodeManagedSettings
        var previousManaged: [ClaudeCodeManagedSettings]?
    }

    private struct Snapshot {
        var url: URL
        var data: Data?
        var permissions: Int?
    }

    public let paths: ClaudeCodeProfilePaths
    private let fileStore: any ClaudeCodeProfileFileStore

    public init(
        paths: ClaudeCodeProfilePaths,
        fileStore: (any ClaudeCodeProfileFileStore)? = nil
    ) {
        self.paths = paths
        self.fileStore =
            fileStore
            ?? DiskClaudeCodeProfileFileStore(
                backupDirectory: paths.backupDirectory
            )
    }

    public func activate(managed: ClaudeCodeManagedSettings) throws {
        let current = try fileStore.snapshot(paths.settings)
        let currentPermissions = try fileStore.permissions(paths.settings)

        if let journal = try readJournal() {
            try reactivateManagedProfile(
                current: current,
                currentPermissions: currentPermissions,
                existingJournal: journal,
                managed: managed
            )
            return
        }

        let activated = try ClaudeCodeSettingsDocument.activating(
            current,
            managed: managed
        )
        let backupURL = current.map { _ in newBackupURL() }
        let journal = Journal(
            version: 1,
            settingsExisted: current != nil,
            backupFilename: backupURL?.lastPathComponent,
            originalPermissions: currentPermissions,
            managed: managed,
            previousManaged: nil
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
        if current == (try ClaudeCodeSettingsDocument.activating(original, managed: journal.managed)) {
            restored = original
        } else {
            restored = try restoringManagedValues(
                current: current,
                original: original,
                signatures: managedSignatures(for: journal)
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

    public func status(
        expected: ClaudeCodeManagedSettings?
    ) throws -> ClaudeCodeProfileStatus {
        guard let journal = try readJournal() else {
            return .inactive
        }
        _ = try originalData(for: journal)
        if journal.previousManaged?.isEmpty == false {
            return .drifted
        }
        // A retired key can still match every remaining expected value.
        // Reapply the profile so the old journal can restore that key.
        if let expected, expected != journal.managed {
            return .drifted
        }
        let managed = expected ?? journal.managed
        return try ClaudeCodeSettingsDocument.isManaged(
            fileStore.snapshot(paths.settings),
            managed: managed
        ) ? .active : .drifted
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

    private func managedSignatures(
        for journal: Journal
    ) -> [ClaudeCodeManagedSettings] {
        ((journal.previousManaged ?? []) + [journal.managed]).reduce(into: []) { signatures, managed in
            if !signatures.contains(managed) {
                signatures.append(managed)
            }
        }
    }

    private func restoringManagedValues(
        current: Data?,
        original: Data?,
        signatures: [ClaudeCodeManagedSettings]
    ) throws -> Data? {
        try signatures.reduce(current) { restored, managed in
            try ClaudeCodeSettingsDocument.restoring(
                current: restored,
                original: original,
                managed: managed
            )
        }
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

    private func journalBackupURL(for journal: Journal) -> URL? {
        guard journal.settingsExisted else {
            return nil
        }
        return try? backupURL(for: journal)
    }

    private func newBackupURL() -> URL {
        let timestamp = String(
            format: "%020.0f",
            Date().timeIntervalSince1970 * 1_000_000
        )
        return paths.backupDirectory.appending(
            path: "settings.json.\(timestamp).\(UUID().uuidString).backup"
        )
    }

    private func pruneBackups(protected: URL?) throws {
        let backups = try fileStore.contents(of: paths.backupDirectory)
            .filter {
                $0.lastPathComponent.hasPrefix("settings.json.")
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

    private func transaction(
        urls: [URL],
        operation: () throws -> Void
    ) throws {
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

extension ClaudeCodeProfileManager {
    private func reactivateManagedProfile(
        current: Data?,
        currentPermissions: Int?,
        existingJournal: Journal,
        managed: ClaudeCodeManagedSettings
    ) throws {
        var journal = existingJournal
        let original = try originalData(for: journal)
        let ownedManaged = managedSignatures(for: journal)
        let restored = try restoringManagedValues(
            current: current,
            original: original,
            signatures: ownedManaged
        )
        let recoveryBaselineChanged = try !ClaudeCodeSettingsDocument.semanticallyMatches(
            restored,
            original
        )
        let recoveryBackupURL: URL?
        if recoveryBaselineChanged, restored != nil {
            recoveryBackupURL =
                journal.settingsExisted
                ? try backupURL(for: journal)
                : newBackupURL()
            journal.settingsExisted = true
            journal.backupFilename = recoveryBackupURL?.lastPathComponent
            journal.originalPermissions = currentPermissions ?? journal.originalPermissions
        } else if recoveryBaselineChanged {
            recoveryBackupURL = nil
            journal.settingsExisted = false
            journal.backupFilename = nil
            journal.originalPermissions = nil
        } else {
            recoveryBackupURL = nil
        }
        let activated = try ClaudeCodeSettingsDocument.activating(
            restored,
            managed: managed
        )
        journal.previousManaged = ownedManaged.filter { $0 != managed }
        journal.managed = managed
        let transitionJournalData = try encode(journal)
        journal.previousManaged = nil
        let finalJournalData = try encode(journal)
        var transactionURLs = [paths.restoreState, paths.settings]
        if let recoveryBackupURL {
            transactionURLs.insert(recoveryBackupURL, at: 0)
        }
        try transaction(urls: transactionURLs) {
            if let restored, let recoveryBackupURL {
                try fileStore.write(
                    restored,
                    to: recoveryBackupURL,
                    permissions: Self.privatePermissions
                )
            }
            try fileStore.write(
                transitionJournalData,
                to: paths.restoreState,
                permissions: Self.privatePermissions
            )
            try fileStore.write(
                activated,
                to: paths.settings,
                permissions: Self.privatePermissions
            )
            try fileStore.write(
                finalJournalData,
                to: paths.restoreState,
                permissions: Self.privatePermissions
            )
        }
        try? pruneBackups(protected: recoveryBackupURL ?? journalBackupURL(for: journal))
    }
}

extension ClaudeCodeProfileManager: ClaudeCodeProfileManaging {}
