public struct ClaudeRoute: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var family: String
    public var createdAt: String
    public var isFamilyDefault: Bool

    public static let all = [
        ClaudeRoute(
            id: "claude-fable-5-1",
            displayName: "Fable",
            family: "fable",
            createdAt: "2026-06-09T00:00:00Z",
            isFamilyDefault: true
        ),
        ClaudeRoute(
            id: "claude-opus-5",
            displayName: "Opus",
            family: "opus",
            createdAt: "2026-07-24T00:00:00Z",
            isFamilyDefault: true
        ),
        ClaudeRoute(
            id: "claude-sonnet-5",
            displayName: "Sonnet",
            family: "sonnet",
            createdAt: "2026-06-30T00:00:00Z",
            isFamilyDefault: true
        ),
        ClaudeRoute(
            id: "claude-haiku-4-5-20251001",
            displayName: "Haiku",
            family: "haiku",
            createdAt: "2025-10-01T00:00:00Z",
            isFamilyDefault: true
        ),
    ]

    /// Label served as the catalog `display_name` to clients. The indicator
    /// arrow marks the slot as a live-switchable alias in client model
    /// pickers; the mapping UI shows the plain name beside its own arrow.
    public func catalogDisplayName(indicator: ModelIndicator, extendedContext: Bool = false) -> String {
        let label = indicator.symbol.map { "\(displayName) \($0)" } ?? displayName
        return extendedContext ? "\(label) [1m]" : label
    }
}
