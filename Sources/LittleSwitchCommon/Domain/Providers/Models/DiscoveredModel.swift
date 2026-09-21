public struct DiscoveredModel: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var maxTokens: Int?
    public var detectedContextWindow: Int?
    public var contextWindowOverride: Int?
    public var supportsImageInput: Bool?

    public init(
        id: String,
        maxTokens: Int? = nil,
        detectedContextWindow: Int? = nil,
        contextWindowOverride: Int? = nil,
        supportsImageInput: Bool? = nil
    ) {
        self.id = id
        self.maxTokens = maxTokens
        self.detectedContextWindow = detectedContextWindow
        self.contextWindowOverride = contextWindowOverride
        self.supportsImageInput = supportsImageInput
    }

    public var effectiveContextWindow: Int? {
        detectedContextWindow ?? contextWindowOverride
    }

    /// A manual declaration is only needed when the provider reports no capacity.
    public var allows1MContextOverride: Bool {
        detectedContextWindow == nil
    }

    public var supports1MContext: Bool {
        effectiveContextWindow.map { $0 >= 1_000_000 } ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case maxTokens = "max_tokens"
        case detectedContextWindow = "detected_context_window"
        case contextWindowOverride = "context_window_override"
        case supportsImageInput = "supports_image_input"
    }
}
