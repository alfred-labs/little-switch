public enum ProviderStatus: String, Codable, Sendable {
    case idle
    case refreshing
    case ready
    case unavailable
}
