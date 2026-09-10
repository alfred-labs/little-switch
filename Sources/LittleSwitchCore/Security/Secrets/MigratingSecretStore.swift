public struct MigratingSecretStore: SecretStore {
    private let primary: any SecretStore
    private let legacy: any SecretStore

    public init(primary: any SecretStore, legacy: any SecretStore) {
        self.primary = primary
        self.legacy = legacy
    }

    public func read(account: SecretAccount) throws -> String? {
        if let value = try primary.read(account: account) {
            return value
        }
        guard let value = try legacy.read(account: account) else {
            return nil
        }
        try primary.write(value, account: account)
        try legacy.delete(account: account)
        return value
    }

    public func write(_ secret: String, account: SecretAccount) throws {
        try primary.write(secret, account: account)
        try legacy.delete(account: account)
    }

    public func delete(account: SecretAccount) throws {
        try primary.delete(account: account)
        try legacy.delete(account: account)
    }
}
