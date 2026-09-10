import Foundation

public struct ClaudeCatalogResponse: Codable, Equatable, Sendable {
    public var data: [ClaudeCatalogModel]
    public var firstID: String?
    public var lastID: String?
    public var hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case data
        case firstID = "first_id"
        case lastID = "last_id"
        case hasMore = "has_more"
    }
}

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
}

public enum ClaudeCatalog {
    public static func make(from snapshot: RoutingSnapshot) -> ClaudeCatalogResponse {
        let targets = snapshot.validTargets
        let models = ClaudeRoute.all.compactMap { route -> ClaudeCatalogModel? in
            guard let target = targets[route.id] else {
                return nil
            }
            return ClaudeCatalogModel(
                id: route.id,
                type: "model",
                displayName: route.catalogDisplayName(indicator: snapshot.modelIndicator),
                createdAt: route.createdAt,
                maxTokens: 64_000,
                maxInputTokens: 200_000,
                supports1M: target.supports1MContext,
                family: route.family,
                isFamilyDefault: route.isFamilyDefault
            )
        }
        return ClaudeCatalogResponse(
            data: models,
            firstID: models.first?.id,
            lastID: models.last?.id,
            hasMore: false
        )
    }

    public static func encode(_ response: ClaudeCatalogResponse) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(response)
    }
}
