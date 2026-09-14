import Foundation

public struct ClaudeCatalogModel: Codable, Equatable, Sendable {
    public var id: String
    public var type: String
    public var displayName: String
    public var createdAt: String
    public var maxTokens: Int
    public var maxInputTokens: Int?
    public var supports1M: Bool
    public var family: String
    public var isFamilyDefault: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case displayName = "display_name"
        case createdAt = "created_at"
        case maxTokens = "max_tokens"
        case maxInputTokens = "max_input_tokens"
        case supports1M = "supports_1m"
        case family = "anthropic_family_tier"
        case isFamilyDefault = "is_family_default"
    }
    package init(
        id: String,
        type: String,
        displayName: String,
        createdAt: String,
        maxTokens: Int,
        maxInputTokens: Int? = nil,
        supports1M: Bool,
        family: String,
        isFamilyDefault: Bool
    ) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.createdAt = createdAt
        self.maxTokens = maxTokens
        self.maxInputTokens = maxInputTokens
        self.supports1M = supports1M
        self.family = family
        self.isFamilyDefault = isFamilyDefault
    }

}
