import Foundation

/// What the last scheduled script run produced for a provider. Failure
/// messages surface in the provider list; successes are silent. The stderr
/// tail of the last run — success or failure — feeds the editor's output pane.
public struct CredentialRefreshOutcome: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case refreshed
        case failed
    }

    public let kind: Kind
    public let message: String?
    public let standardError: String

    public init(
        kind: Kind,
        message: String? = nil,
        standardError: String = ""
    ) {
        self.kind = kind
        self.message = message
        self.standardError = standardError
    }
}
