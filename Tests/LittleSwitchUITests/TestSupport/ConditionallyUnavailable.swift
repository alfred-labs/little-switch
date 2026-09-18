import Foundation
import Testing

/// GitHub's macOS 27 preview runner cannot host SwiftUI AX focus in an
/// unactivated, offscreen process: SwiftUICore logs "Failed to focus
/// AccessibilityNode ... please file a bug report" for those interactions.
/// Keep every assertion locally, and skip only where the bug cannot be
/// reproduced. Remove when the runner image or framework behaves like macOS 26.
enum ConditionallyUnavailable {
    static var hasAxFocusRunnerLimitation: Bool {
        ProcessInfo.processInfo.environment["LITTLESWITCH_AX_FOCUS_RUNNER_LIMITATION"] == "github-macos-27"
    }

    /// `Trait.disabled(if:)` does not exist in the runner's Swift Testing
    /// build (2078), so the skip has to happen inside the test body.
    static func skipWhenAxFocusUnavailable(_ reason: String) -> Bool {
        guard hasAxFocusRunnerLimitation else { return false }
        withKnownIssue {
            Issue.record(UnavailableOnRunner(reason: reason))
        }
        return true
    }
}

private struct UnavailableOnRunner: Error {
    let reason: String
}
