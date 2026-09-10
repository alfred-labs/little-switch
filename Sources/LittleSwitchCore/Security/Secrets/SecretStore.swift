import Foundation

public protocol SecretStore: Sendable {
    func read(account: SecretAccount) throws -> String?
    func write(_ secret: String, account: SecretAccount) throws
    func delete(account: SecretAccount) throws
}

extension SecretStore {
    public func read(providerID: UUID) throws -> String? {
        try read(account: .provider(providerID))
    }

    public func write(_ secret: String, providerID: UUID) throws {
        try write(secret, account: .provider(providerID))
    }

    public func delete(providerID: UUID) throws {
        try delete(account: .provider(providerID))
    }

    /// Legacy keychain script retirement: pre-0.1.5 versions stored the whole
    /// script beside the token; only deletion remains — scripts are paths in
    /// the configuration now, and the keychain keeps tokens only.
    public func deleteScript(providerID: UUID) throws {
        try delete(account: .script(providerID))
    }
}
