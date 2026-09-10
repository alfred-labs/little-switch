public enum OpenCodeConnectionStatus: Equatable, Sendable {
    case disconnected
    case connected
    case needsAttention
    case recoveryAvailable
    case recoveryUnavailable
}
