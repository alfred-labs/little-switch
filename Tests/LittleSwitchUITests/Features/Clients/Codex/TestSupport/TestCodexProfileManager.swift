import Foundation
import LittleSwitchCommon
import LittleSwitchCore

final class TestCodexProfileManager: CodexProfileManaging, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case activateInjected
        case restoreInjected
    }

    private let lock = NSLock()
    private var active = false
    private var legacyActive = false
    private var legacyWebSearch = false
    private var activationInputs: [CodexConfiguration] = []
    private var signatureInputs: [CodexManagedProfileSignature] = []
    private var statusInputs: [CodexManagedProfileSignature] = []
    private var restoreCalls = 0
    private var shouldFailNextActivation = false
    private var shouldFailNextRestore = false
    var eventLog: SharedEventLog?

    init(active: Bool = false, legacyActiveWithoutConcurrency: Bool = false, legacyWebSearch: Bool = false) {
        self.active = active
        legacyActive = legacyActiveWithoutConcurrency
        self.legacyWebSearch = legacyWebSearch
    }

    var activations: [CodexConfiguration] {
        lock.withLock { activationInputs }
    }

    var signatures: [CodexManagedProfileSignature] {
        lock.withLock { signatureInputs }
    }

    var expectedStatuses: [CodexManagedProfileSignature] {
        lock.withLock { statusInputs }
    }

    var restoreCount: Int {
        lock.withLock { restoreCalls }
    }

    func activate(providers: [Provider], configuration: CodexConfiguration) throws {
        let signature = try CodexManagedProfileSignature.resolve(
            providers: providers,
            configuration: configuration
        )
        try activate(
            providers: providers,
            configuration: configuration,
            signature: signature
        )
    }

    func activate(
        providers: [Provider],
        configuration: CodexConfiguration,
        signature: CodexManagedProfileSignature
    ) throws {
        _ = providers
        try lock.withLock {
            if shouldFailNextActivation {
                shouldFailNextActivation = false
                throw Error.activateInjected
            }
            activationInputs.append(configuration)
            signatureInputs.append(signature)
            active = true
            legacyActive = signature.maximumConcurrentThreadsPerSession == nil
            legacyWebSearch = signature.webSearchMode == nil
        }
    }

    func restore() throws {
        try lock.withLock {
            if shouldFailNextRestore {
                shouldFailNextRestore = false
                throw Error.restoreInjected
            }
            restoreCalls += 1
            active = false
            legacyActive = false
            legacyWebSearch = false
        }
    }

    func isActive(providers: [Provider], configuration: CodexConfiguration) throws -> Bool {
        _ = providers
        _ = configuration
        return lock.withLock { active || legacyActive || legacyWebSearch }
    }

    func status(
        providers: [Provider],
        configuration: CodexConfiguration,
        expected: CodexManagedProfileSignature
    ) throws -> CodexProfileStatus {
        _ = providers
        _ = configuration
        return lock.withLock {
            statusInputs.append(expected)
            var applied = expected
            if legacyActive {
                applied = applied.withoutNativeConcurrency()
            }
            if legacyWebSearch {
                applied = applied.withoutManagedWebSearch()
            }
            if applied != expected {
                return .requiresUpdate(applied)
            }
            return active ? .active(expected) : .inactive
        }
    }

    func failNextActivation() {
        lock.withLock { shouldFailNextActivation = true }
    }

    func failNextRestore() {
        lock.withLock { shouldFailNextRestore = true }
    }

    func enableDesktopMaximumEffort() throws {
        eventLog?.append("codex-desktop-patch")
    }
}
