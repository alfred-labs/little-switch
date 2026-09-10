import Foundation
import LittleSwitchCore

final class TestOpenCodeProfileManager: OpenCodeProfileManaging, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case activateInjected
        case restoreInjected
        case statusInjected
    }

    private let lock = NSLock()
    private var currentStatus: OpenCodeProfileStatus
    private var activationInputs: [OpenCodeManagedSettings] = []
    private var restoreCalls = 0
    private var statusInputs: [OpenCodeManagedSettings?] = []
    private var shouldFailNextActivation = false
    private var shouldFailNextRestore = false
    private var shouldFailNextRollback = false
    private var shouldFailStatus = false

    init(status: OpenCodeProfileStatus = .inactive) {
        currentStatus = status
    }

    var activations: [OpenCodeManagedSettings] {
        lock.withLock { activationInputs }
    }

    var restoreCount: Int {
        lock.withLock { restoreCalls }
    }

    var expectedStatuses: [OpenCodeManagedSettings?] {
        lock.withLock { statusInputs }
    }

    func activate(managed: OpenCodeManagedSettings) throws {
        try activate(managed: managed) {}
    }

    func activate(managed: OpenCodeManagedSettings, committing: () throws -> Void) throws {
        let previous = try lock.withLock {
            if shouldFailNextActivation {
                shouldFailNextActivation = false
                throw Error.activateInjected
            }
            let previous = (status: currentStatus, activations: activationInputs)
            activationInputs.append(managed)
            currentStatus = .active
            return previous
        }
        do {
            try committing()
        } catch {
            try lock.withLock {
                if shouldFailNextRollback {
                    shouldFailNextRollback = false
                    throw OpenCodeProfileManager.Error.rollbackFailed
                }
                currentStatus = previous.status
                activationInputs = previous.activations
            }
            throw error
        }
    }

    func restore() throws {
        try lock.withLock {
            if shouldFailNextRestore {
                shouldFailNextRestore = false
                throw Error.restoreInjected
            }
            restoreCalls += 1
            currentStatus = .inactive
        }
    }

    func status(expected: OpenCodeManagedSettings?) throws -> OpenCodeProfileStatus {
        try lock.withLock {
            statusInputs.append(expected)
            if shouldFailStatus {
                throw Error.statusInjected
            }
            return currentStatus
        }
    }

    func managedSettings() throws -> OpenCodeManagedSettings? {
        lock.withLock { activationInputs.last }
    }

    func failNextActivation() {
        lock.withLock { shouldFailNextActivation = true }
    }

    func failNextRollback() {
        lock.withLock { shouldFailNextRollback = true }
    }

    func failNextRestore() {
        lock.withLock { shouldFailNextRestore = true }
    }

    func failStatus() {
        lock.withLock { shouldFailStatus = true }
    }
}
