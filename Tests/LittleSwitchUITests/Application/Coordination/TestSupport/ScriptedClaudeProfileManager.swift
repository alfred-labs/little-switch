import Foundation
import LittleSwitchCommon
import LittleSwitchCore

final class ScriptedClaudeProfileManager: ClaudeProfileManaging, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case activateInjected
        case restoreInjected
        case statusInjected
    }

    private let lock = NSLock()
    private var active: Bool
    private var activationAttempt = 0
    private var restoreAttempt = 0
    private var failingActivationAttempts: Set<Int> = []
    private var failingRestoreAttempts: Set<Int> = []
    private var statusShouldFail = false

    init(active: Bool = false) {
        self.active = active
    }

    var activationCount: Int {
        lock.withLock { activationAttempt }
    }

    var restoreCount: Int {
        lock.withLock { restoreAttempt }
    }

    func activate(autoMode: Bool, tlsEnabled: Bool) throws {
        _ = autoMode
        try lock.withLock {
            activationAttempt += 1
            guard !failingActivationAttempts.contains(activationAttempt) else {
                throw Error.activateInjected
            }
            active = true
        }
    }

    func restore() throws {
        try lock.withLock {
            restoreAttempt += 1
            guard !failingRestoreAttempts.contains(restoreAttempt) else {
                throw Error.restoreInjected
            }
            active = false
        }
    }

    func isActive(autoMode: Bool) throws -> Bool {
        _ = autoMode
        return try lock.withLock {
            guard !statusShouldFail else { throw Error.statusInjected }
            return active
        }
    }

    func failActivations(on attempts: Set<Int>) {
        lock.withLock { failingActivationAttempts = attempts }
    }

    func catalogMatches(_ choices: [ClaudeCodeModelChoice]) throws -> Bool {
        try isActive(autoMode: true)
    }

    func updateCatalog(_ choices: [ClaudeCodeModelChoice], autoMode: Bool) throws {
        guard try isActive(autoMode: autoMode) else { throw ClaudeProfileManager.Error.inactiveProfile }
    }

    func failRestores(on attempts: Set<Int>) {
        lock.withLock { failingRestoreAttempts = attempts }
    }

    func failStatus() {
        lock.withLock { statusShouldFail = true }
    }
}
