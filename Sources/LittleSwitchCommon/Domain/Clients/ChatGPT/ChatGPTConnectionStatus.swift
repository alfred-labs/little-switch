/// A saved connection is intent; only an explicit managed launch is connected.
public enum ChatGPTConnectionStatus: Equatable, Sendable {
    case disconnected
    case ready
    case connected
    case connecting
    case disconnecting
    case needsAttention
}
