public struct OpenCodeConfiguration: Codable, Equatable, Sendable {
    public var connected: Bool
    public var defaultModel: ModelMapping?

    public static let disconnected = OpenCodeConfiguration()

    public init(
        connected: Bool = false,
        defaultModel: ModelMapping? = nil
    ) {
        self.connected = connected
        self.defaultModel = defaultModel
    }

    public func availableModels(
        in providers: [Provider],
        codex: CodexConfiguration
    ) -> [CodexModelTarget] {
        codex.exposedModels(in: providers)
    }

    public func normalized(
        providers: [Provider],
        codex: CodexConfiguration
    ) -> OpenCodeConfiguration {
        let available = availableModels(in: providers, codex: codex)
        guard !available.contains(where: { $0.mapping == defaultModel }) else {
            return self
        }

        var result = self
        let codexDefault = codex.resolvedDefaultModel(in: providers)
        if let codexDefault {
            if available.contains(where: { $0.mapping == codexDefault }) {
                result.defaultModel = codexDefault
                return result
            }
        }
        result.defaultModel = available.first?.mapping
        return result
    }
}
