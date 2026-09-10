import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex profile protocol defaults")
struct CodexProfileProtocolDefaultsTests {
    @Test("Legacy conformers receive signature activation and derive status from isActive")
    func legacyConformerDefaults() throws {
        let fixture = try CodexProfileFixture.make(maximumParallelRequests: 7)
        defer { fixture.remove() }
        let signature = try CodexManagedProfileSignature.resolve(
            providers: fixture.providers,
            configuration: fixture.configuration
        )
        let manager = LegacyCodexProfileManager()

        try manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration,
            signature: signature
        )
        #expect(manager.activationCount == 1)
        #expect(
            try manager.status(
                providers: fixture.providers,
                configuration: fixture.configuration,
                expected: signature
            ) == .active(signature)
        )

        manager.active = false
        #expect(
            try manager.status(
                providers: fixture.providers,
                configuration: fixture.configuration,
                expected: signature
            ) == .inactive
        )
    }
}

private final class LegacyCodexProfileManager: CodexProfileManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var activations = 0
    private var isCurrentlyActive = true

    var activationCount: Int {
        lock.withLock { activations }
    }

    var active: Bool {
        get { lock.withLock { isCurrentlyActive } }
        set { lock.withLock { isCurrentlyActive = newValue } }
    }

    func activate(providers: [Provider], configuration: CodexConfiguration) throws {
        _ = providers
        _ = configuration
        lock.withLock { activations += 1 }
    }

    func restore() throws {}

    func isActive(providers: [Provider], configuration: CodexConfiguration) throws -> Bool {
        _ = providers
        _ = configuration
        return active
    }
}
