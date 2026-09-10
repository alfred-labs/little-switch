import Foundation

public protocol ApplicationRelaunching: Sendable {
    @MainActor func isRunning() -> Bool
    @MainActor func quitAndWait() async throws
    @MainActor func open() async throws
}

package enum ApplicationRelaunchOutcome: Sendable, Equatable {
    /// The application was running and came back up.
    case relaunched
    /// Nothing to do: the application was not running, so it will read its
    /// settings at its next launch.
    case notRunning
    /// The application was running but quit or reopen failed; it may still be
    /// running with stale settings.
    case failed
}

extension ApplicationRelaunching {
    @MainActor @discardableResult package func relaunch() async -> ApplicationRelaunchOutcome {
        guard isRunning() else {
            return .notRunning
        }
        do {
            try await quitAndWait()
            try await open()
            return .relaunched
        } catch {
            return .failed
        }
    }
}
