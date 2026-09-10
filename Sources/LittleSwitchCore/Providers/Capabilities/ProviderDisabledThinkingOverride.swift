/// Compatibility for Anthropic requests that explicitly disable thinking.
/// Low effort is the product default; pass through is an explicit opt-out
/// that preserves the caller's thinking and effort parameters.
public enum ProviderDisabledThinkingOverride: String, Codable, Sendable {
    case lowEffort
    case passthrough

    /// The behavior applied when a stored provider predates the setting.
    public static let `default`: ProviderDisabledThinkingOverride = .lowEffort
}
