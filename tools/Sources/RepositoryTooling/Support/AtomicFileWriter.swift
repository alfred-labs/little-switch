import Darwin
import Foundation

package enum AtomicFileWriter {
    package final class Replacement {
        private let destination: URL
        private let expected: Data?
        private var temporary: URL?

        fileprivate init(destination: URL, expected: Data?, temporary: URL?) {
            self.destination = destination
            self.expected = expected
            self.temporary = temporary
        }

        deinit {
            if let temporary { try? FileManager.default.removeItem(at: temporary) }
        }

        package func commit() throws {
            try AtomicFileWriter.check(destination, expected: expected)
            guard let temporary else { return }
            guard rename(temporary.path, destination.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            self.temporary = nil
        }
    }

    package static func prepare(contents: Data, at destination: URL, expectedContents: Data?) throws -> Replacement {
        try check(destination, expected: expectedContents)
        guard contents != expectedContents else {
            return Replacement(destination: destination, expected: expectedContents, temporary: nil)
        }
        let mode: mode_t
        if expectedContents != nil {
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            mode = mode_t((attributes[.posixPermissions] as? NSNumber)?.uint32Value ?? 0o644)
        } else {
            mode = 0o644
        }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".littleswitch-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let replacement = Replacement(destination: destination, expected: expectedContents, temporary: temporary)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        guard fchmod(descriptor, mode) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        try handle.write(contentsOf: contents)
        try handle.synchronize()
        return replacement
    }

    private static func check(_ destination: URL, expected: Data?) throws {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path) {
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw ReleaseValidationError("Release output must be a regular file, not a directory or symbolic link")
            }
            guard let expected, try Data(contentsOf: destination) == expected else {
                throw ReleaseValidationError("The release output changed while preparing the update")
            }
        } else if expected != nil {
            throw ReleaseValidationError("The release output changed while preparing the update")
        }
    }
}
