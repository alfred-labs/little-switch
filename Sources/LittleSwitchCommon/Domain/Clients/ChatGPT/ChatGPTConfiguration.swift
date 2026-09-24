public struct ChatGPTConfiguration: Codable, Equatable, Sendable {
    public var connected: Bool

    public static let disconnected = ChatGPTConfiguration()

    public init(connected: Bool = false) {
        self.connected = connected
    }
}
