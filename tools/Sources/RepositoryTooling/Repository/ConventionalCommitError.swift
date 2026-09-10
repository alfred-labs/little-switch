import Foundation

package enum ConventionalCommitError: Error, Equatable, LocalizedError, Sendable {
    case invalidSubject(String)

    package var errorDescription: String? {
        switch self {
        case .invalidSubject(let subject):
            return [
                "Commit message must follow the Conventional Commit format: type(scope)!?: subject",
                "Allowed types: \(ConventionalCommit.allowedTypes.joined(separator: ", "))",
                "Examples: feat(gateway): route Claude models, fix: restore Claude profile, chore(release): LittleSwitch v0.1.0",
                "Received: \(subject.isEmpty ? "<empty>" : subject)",
            ].joined(separator: "\n")
        }
    }
}
