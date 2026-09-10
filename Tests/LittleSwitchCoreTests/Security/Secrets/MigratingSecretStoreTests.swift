import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Migrating secret service")
struct MigratingSecretStoreTests {
    @Test("Migrating secret store returns primary values without touching legacy values")
    func primarySecretHit() throws {
        let account = SecretAccount.provider(UUID())
        let primary = MemorySecretStore()
        let legacy = MemorySecretStore()
        try primary.write("primary", account: account)
        try legacy.write("legacy", account: account)
        let store = MigratingSecretStore(primary: primary, legacy: legacy)

        #expect(try store.read(account: account) == "primary")
        #expect(try primary.read(account: account) == "primary")
        #expect(try legacy.read(account: account) == "legacy")
    }

    @Test("Migrating secret store moves a legacy value into the primary store")
    func legacySecretMigration() throws {
        let account = SecretAccount.webSearch(.firecrawl)
        let primary = MemorySecretStore()
        let legacy = MemorySecretStore()
        try legacy.write("legacy", account: account)
        let store = MigratingSecretStore(primary: primary, legacy: legacy)

        #expect(try store.read(account: account) == "legacy")
        #expect(try primary.read(account: account) == "legacy")
        #expect(try legacy.read(account: account) == nil)
    }

    @Test("Migrating secret store reports a value missing from both stores")
    func missingMigratedSecret() throws {
        let account = SecretAccount.provider(UUID())
        let store = MigratingSecretStore(
            primary: MemorySecretStore(),
            legacy: MemorySecretStore()
        )

        #expect(try store.read(account: account) == nil)
    }

    @Test("Migrating secret writes and deletes reconcile both stores")
    func migratingSecretWritesAndDeletes() throws {
        let account = SecretAccount.provider(UUID())
        let primary = MemorySecretStore()
        let legacy = MemorySecretStore()
        try legacy.write("legacy", account: account)
        let store = MigratingSecretStore(primary: primary, legacy: legacy)

        try store.write("replacement", account: account)
        #expect(try primary.read(account: account) == "replacement")
        #expect(try legacy.read(account: account) == nil)
        try legacy.write("stale", account: account)
        try store.delete(account: account)
        #expect(try primary.read(account: account) == nil)
        #expect(try legacy.read(account: account) == nil)
    }
}
