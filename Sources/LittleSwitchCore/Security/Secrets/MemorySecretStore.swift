import Foundation

public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SecretAccount: String] = [:]

    public init() {}

    public func read(account: SecretAccount) throws -> String? {
        lock.withLock { values[account] }
    }

    public func write(_ secret: String, account: SecretAccount) throws {
        lock.withLock { values[account] = secret }
    }

    public func delete(account: SecretAccount) throws {
        _ = lock.withLock { values.removeValue(forKey: account) }
    }
}
