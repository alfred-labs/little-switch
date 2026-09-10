import Darwin
import Foundation

/// Persists new directory entries before a final device-wide storage barrier.
enum ConfigurationMigrationBackupSync {
    enum Kind: Equatable, Sendable { case directory, file }

    /// The injected operation returns zero or a POSIX error number, matching
    /// AtomicFileWriter's syscall boundary without exposing ambient errno.
    static func synchronize(
        _ destination: URL,
        operation: @Sendable (Int32, Kind) -> Int32 = systemSynchronize
    ) throws {
        // Foundation can abbreviate /private/tmp to the symbolic /tmp again.
        // Use the physical path so O_NOFOLLOW can validate every directory.
        guard let resolvedParent = Darwin.realpath(destination.deletingLastPathComponent().path, nil) else {
            throw posixError(errno)
        }
        defer { Darwin.free(resolvedParent) }
        var directory = URL(filePath: String(cString: resolvedParent), directoryHint: .isDirectory)
        let file = directory.appending(path: destination.lastPathComponent)
        while true {
            try synchronizeDescriptor(at: directory, kind: .directory, operation: operation)
            // URL's parent of / is /.. rather than /, so stop explicitly.
            if directory.path == "/" { break }
            directory = directory.deletingLastPathComponent()
        }
        // On Darwin F_FULLFSYNC drains and orders the earlier fsync writes on
        // this device, including the newly created backup directories and link.
        try synchronizeDescriptor(at: file, kind: .file, operation: operation)
    }

    private static func synchronizeDescriptor(
        at url: URL,
        kind: Kind,
        operation: @Sendable (Int32, Kind) -> Int32
    ) throws {
        let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (kind == .directory ? O_DIRECTORY : 0)
        let descriptor = Darwin.open(url.path, flags)
        guard descriptor >= 0 else {
            throw posixError(errno)
        }
        defer { _ = Darwin.close(descriptor) }
        let error = operation(descriptor, kind)
        guard error == 0 else {
            throw posixError(error)
        }
    }

    private static func posixError(_ code: Int32) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }

    private static func systemSynchronize(_ descriptor: Int32, kind: Kind) -> Int32 {
        let result =
            switch kind {
            case .directory: Darwin.fsync(descriptor)
            case .file: Darwin.fcntl(descriptor, F_FULLFSYNC)
            }
        return result == 0 ? 0 : errno
    }
}
