import Foundation

struct RepositoryPolicyError: Error, Equatable, LocalizedError, Sendable {
    let issues: [String]

    var errorDescription: String? { issues.joined(separator: "\n") }
}
