public enum ClaudeCodeConnectionStatus: Equatable, Sendable {
    case disconnected
    case connected
    case needsAttention
    case recoveryAvailable
    case recoveryUnavailable
}
