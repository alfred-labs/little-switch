import Foundation

package struct ReleaseValidationError: Error, LocalizedError, Equatable {
    package let message: String

    package init(_ message: String) {
        self.message = message
    }

    package var errorDescription: String? { message }
}
