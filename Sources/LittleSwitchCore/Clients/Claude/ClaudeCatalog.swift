import Foundation
import LittleSwitchCommon

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
