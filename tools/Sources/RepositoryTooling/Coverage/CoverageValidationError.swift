import Foundation

package struct CoverageValidationError: Error, Equatable, LocalizedError, Sendable {
    package let message: String

    package init(_ message: String) {
        self.message = message
    }

    package var errorDescription: String? { message }
}
