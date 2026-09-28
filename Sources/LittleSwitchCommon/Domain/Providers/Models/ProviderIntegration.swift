/// The provider protocol integration, independent of its authentication.
public enum ProviderIntegration: String, Codable, CaseIterable, Sendable {
    case openAICompatible
    case anthropic
    case gemini
}
