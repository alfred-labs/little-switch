import Foundation
import LittleSwitchCommon

@testable import LittleSwitchCore

final class FailNextConfigurationStore: ConfigurationStoring, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case injected
    }

    private let lock = NSLock()
    private let backing: ConfigurationStore
    private var shouldFailNextSave = false
    private var successfulSavesBeforeFailure = 0
    private var consecutiveFailures = 0

    init(backing: ConfigurationStore) {
        self.backing = backing
    }

    func load() throws -> AppConfiguration {
        try backing.load()
    }

    func save(_ configuration: AppConfiguration) throws {
        let shouldFail = lock.withLock {
            if successfulSavesBeforeFailure > 0 {
                successfulSavesBeforeFailure -= 1
                return false
            }
            if shouldFailNextSave {
                shouldFailNextSave = false
                return true
            }
            if consecutiveFailures > 0 {
                consecutiveFailures -= 1
                return true
            }
            return false
        }
        guard !shouldFail else {
            throw Error.injected
        }
        try backing.save(configuration)
    }

    func failNextSave() {
        lock.withLock {
            shouldFailNextSave = true
        }
    }

    /// Fails the next `count` saves after `skipping` successful ones — for
    /// exercising rollback paths that save a second time after a first
    /// committed save.
    func failSaves(skipping: Int, count: Int = 1) {
        lock.withLock {
            successfulSavesBeforeFailure = skipping
            consecutiveFailures = count
        }
    }
}
