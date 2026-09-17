import Foundation

/// GitHub's macOS 27 preview runner cannot host SwiftUI AX focus in an
/// unactivated, offscreen process: SwiftUICore logs "Failed to focus
/// AccessibilityNode ... please file a bug report" for those interactions.
/// Keep every assertion locally, and skip only where the bug cannot be
/// reproduced. Remove when the runner image or framework behaves like macOS 26.
enum ConditionallyUnavailable {
    static var onRunner: Bool {
        ProcessInfo.processInfo.environment["CI"] == "true"
    }
}
