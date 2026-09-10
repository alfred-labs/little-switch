import Foundation

final class PermissionCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCall: (permissions: Int, url: URL)?

    var call: (permissions: Int, url: URL)? {
        lock.withLock { recordedCall }
    }

    func reject(permissions: Int, url: URL) throws {
        lock.withLock {
            recordedCall = (permissions, url)
        }
        throw POSIXError(.EACCES)
    }
}
