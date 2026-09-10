import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Secret migration failure ordering")
struct SecretMigrationFailureTests {
    @Test("A failed primary write preserves the only legacy copy", arguments: [true, false])
    func failedWrite(migratingRead: Bool) throws {
        let account = SecretAccount.provider(UUID())
        let primary = MemorySecretStore()
        let legacy = MemorySecretStore()
        try legacy.write("synthetic-legacy", account: account)
        let store = MigratingSecretStore(primary: FailingSecretStore(storage: primary, failure: .write), legacy: legacy)

        #expect(throws: SecretFixtureFailure.write) {
            if migratingRead {
                _ = try store.read(account: account)
            } else {
                try store.write("synthetic-new", account: account)
            }
        }
        #expect(try primary.read(account: account) == nil)
        #expect(try legacy.read(account: account) == "synthetic-legacy")
    }

    @Test("Legacy cleanup only runs after a successful primary write")
    func failedLegacyCleanup() throws {
        let account = SecretAccount.provider(UUID())
        let primary = MemorySecretStore()
        let legacy = MemorySecretStore()
        try legacy.write("synthetic-legacy", account: account)
        let store = MigratingSecretStore(
            primary: primary, legacy: FailingSecretStore(storage: legacy, failure: .delete))

        #expect(throws: SecretFixtureFailure.delete) { try store.read(account: account) }
        #expect(try primary.read(account: account) == "synthetic-legacy")
        #expect(try legacy.read(account: account) == "synthetic-legacy")
        // The next read succeeds from the committed primary copy without retrying legacy cleanup.
        #expect(try store.read(account: account) == "synthetic-legacy")
    }

    @Test("Primary deletion failure leaves the legacy copy untouched")
    func failedDelete() throws {
        let account = SecretAccount.provider(UUID())
        let primary = MemorySecretStore()
        let legacy = MemorySecretStore()
        try primary.write("synthetic-primary", account: account)
        try legacy.write("synthetic-legacy", account: account)
        let store = MigratingSecretStore(
            primary: FailingSecretStore(storage: primary, failure: .delete), legacy: legacy)

        #expect(throws: SecretFixtureFailure.delete) { try store.delete(account: account) }
        #expect(try primary.read(account: account) == "synthetic-primary")
        #expect(try legacy.read(account: account) == "synthetic-legacy")
    }

    @Test("Read failures propagate without manufacturing a missing secret", arguments: [true, false])
    func failedRead(primaryFails: Bool) throws {
        let account = SecretAccount.provider(UUID())
        let primary = MemorySecretStore()
        let legacy = MemorySecretStore()
        try legacy.write("synthetic-legacy", account: account)
        let store = MigratingSecretStore(
            primary: primaryFails ? FailingSecretStore(storage: primary, failure: .read) : primary,
            legacy: primaryFails ? legacy : FailingSecretStore(storage: legacy, failure: .read))
        #expect(throws: SecretFixtureFailure.read) { try store.read(account: account) }
        #expect(try primary.read(account: account) == nil)
        #expect(try legacy.read(account: account) == "synthetic-legacy")
    }
}

private enum SecretFixtureFailure: Error { case read, write, delete }

private struct FailingSecretStore: SecretStore {
    let storage: MemorySecretStore
    let failure: SecretFixtureFailure

    func read(account: SecretAccount) throws -> String? {
        if failure == .read { throw failure }
        return try storage.read(account: account)
    }

    func write(_ secret: String, account: SecretAccount) throws {
        if failure == .write { throw failure }
        try storage.write(secret, account: account)
    }

    func delete(account: SecretAccount) throws {
        if failure == .delete { throw failure }
        try storage.delete(account: account)
    }
}
