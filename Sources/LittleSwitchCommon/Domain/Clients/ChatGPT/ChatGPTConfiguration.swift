public struct ChatGPTConfiguration: Codable, Equatable, Sendable {
    public var connected: Bool
    public var model: ModelMapping?

    public static let disconnected = ChatGPTConfiguration()

    public init(connected: Bool = false, model: ModelMapping? = nil) {
        self.connected = connected
        self.model = model
    }

    public func resolvedModel(in providers: [Provider]) -> CodexModelTarget? {
        guard let model else { return nil }
        let matches = providers.filter { $0.id == model.providerID }.flatMap { provider in
            provider.models.filter { $0.id == model.modelID }.map { CodexModelTarget(provider: provider, model: $0) }
        }
        return matches.count == 1 ? matches.first : nil
    }
}
