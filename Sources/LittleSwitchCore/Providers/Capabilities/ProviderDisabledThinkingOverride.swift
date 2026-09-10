/// Compatibility for Anthropic requests that explicitly disable thinking.
public enum ProviderDisabledThinkingOverride: String, Codable, Sendable {
    case lowEffort
}
