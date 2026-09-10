import Foundation
import LittleSwitchSearch

public struct WebSearchInput: Equatable, Sendable {
    public var configuration: WebSearchConfiguration
    public var credential: String?

    public init(
        configuration: WebSearchConfiguration,
        credential: String? = nil
    ) {
        self.configuration = configuration
        self.credential = credential
    }
}

extension WebSearchInput {
    /// True when the draft would write nothing: the same configuration and no
    /// new credential typed. Apply stays disabled in that case, the way the
    /// application panes already behave.
    public func matches(_ saved: WebSearchConfiguration) -> Bool {
        let trimmed = credential?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNewCredential = !(trimmed ?? "").isEmpty
        return !hasNewCredential && configuration == saved
    }
}
