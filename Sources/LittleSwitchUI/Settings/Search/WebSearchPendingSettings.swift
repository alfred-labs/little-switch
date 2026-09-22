import LittleSwitchCommon

/// Memory-only edits shared with the coordinator. The key itself stays in the active pane.
public struct WebSearchPendingSettings: Equatable, Sendable {
    public var configuration: WebSearchConfiguration
    public var hasTypedCredential: Bool

    public init(configuration: WebSearchConfiguration, hasTypedCredential: Bool = false) {
        self.configuration = configuration
        self.hasTypedCredential = hasTypedCredential
    }

    func matches(_ saved: WebSearchConfiguration) -> Bool {
        configuration == saved && !hasTypedCredential
    }
}
