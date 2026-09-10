import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Product identity")
struct ProductIdentityTests {
    @Test("Canonical values match the LittleSwitch product")
    func canonicalValues() {
        #expect(ProductIdentity.displayName == "LittleSwitch")
        #expect(ProductIdentity.bundleIdentifier == "com.alfredlabs.littleswitch")
        #expect(ProductIdentity.applicationSupportDirectoryName == "LittleSwitch")
        #expect(ProductIdentity.keychainService == "com.alfredlabs.littleswitch")
        #expect(ProductIdentity.gatewayServerName == "LittleSwitch")
        #expect(ProductIdentity.gatewayAPIKey == "little-switch")
        #expect(ProductIdentity.gatewayHealthPath == "/health")
        #expect(ProductIdentity.logSubsystem == "com.alfredlabs.littleswitch")
    }

    @Test("The gateway's own paths are recognized for usage accounting")
    func internalGatewayPaths() {
        #expect(ProductIdentity.gatewayMetricsPath == "/metrics")
        #expect(ProductIdentity.gatewayAPIPathPrefix == "/api/")
        #expect(ProductIdentity.legacyGatewayInternalPathPrefix == "/_little_switch/")

        #expect(ProductIdentity.isInternalGatewayPath("/health"))
        #expect(ProductIdentity.isInternalGatewayPath("/metrics"))
        #expect(ProductIdentity.isInternalGatewayPath("/api/about"))
        #expect(ProductIdentity.isInternalGatewayPath("/api/web-search"))
        #expect(ProductIdentity.isInternalGatewayPath("/_little_switch/health"))
        #expect(ProductIdentity.isInternalGatewayPath("/_little_switch/web_search"))
        #expect(!ProductIdentity.isInternalGatewayPath("/v1/messages"))
        #expect(!ProductIdentity.isInternalGatewayPath("/unknown"))
    }

    @Test("Existing Application Support data moves to the canonical directory")
    func migratesApplicationSupportDirectory() throws {
        let base = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-product-identity-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appending(
            path: ProductIdentity.Legacy.ModelSwitch.applicationSupportDirectoryName,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("configuration".utf8).write(to: legacy.appending(path: "config.json"))

        let root = try ProductIdentity.applicationSupportRoot(
            in: base,
            fileManager: .default
        )

        #expect(root.lastPathComponent == "LittleSwitch")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "config.json").path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("An existing canonical directory wins over legacy data")
    func preservesCanonicalApplicationSupportDirectory() throws {
        let base = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-product-identity-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: base) }
        let canonical = base.appending(
            path: ProductIdentity.applicationSupportDirectoryName,
            directoryHint: .isDirectory
        )
        let legacy = base.appending(
            path: ProductIdentity.Legacy.ModelSwitch.applicationSupportDirectoryName,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        let root = try ProductIdentity.applicationSupportRoot(
            in: base,
            fileManager: .default
        )

        #expect(root == canonical)
        #expect(FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("Legacy credentials migrate to the canonical store on first read")
    func migratesLegacyCredential() throws {
        let account = SecretAccount.provider(UUID())
        let canonical = MemorySecretStore()
        let legacy = MemorySecretStore()
        try legacy.write("secret", account: account)
        let store = MigratingSecretStore(primary: canonical, legacy: legacy)

        #expect(try store.read(account: account) == "secret")
        #expect(try canonical.read(account: account) == "secret")
        #expect(try legacy.read(account: account) == nil)
    }
}
