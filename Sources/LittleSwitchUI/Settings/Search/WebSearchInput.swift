import Foundation
import LittleSwitchCommon
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
    var pendingSettings: WebSearchPendingSettings {
        WebSearchPendingSettings(
            configuration: configuration,
            hasTypedCredential: !(credential?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        )
    }

    /// True when the draft would write nothing: the same configuration and no
    /// new credential typed. Apply stays disabled in that case, the way the
    /// application panes already behave.
    public func matches(_ saved: WebSearchConfiguration) -> Bool {
        pendingSettings.matches(saved)
    }
}
