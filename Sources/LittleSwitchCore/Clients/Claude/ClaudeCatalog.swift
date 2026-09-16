import Foundation
import LittleSwitchCommon

public enum ClaudeCatalog {
    package enum ContextPresentation: Equatable, Sendable {
        case capabilities
        case canonicalFamilyChoices
    }

    package static func make(
        from snapshot: RoutingSnapshot,
        contextPresentation: ContextPresentation = .capabilities
    ) -> ClaudeCatalogResponse {
        let targets = snapshot.validTargets
        let models = ClaudeRoute.all.compactMap { route -> ClaudeCatalogModel? in
            guard let target = targets[route.id] else {
                return nil
            }
            var model = ClaudeCatalogModel(
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
            guard contextPresentation == .canonicalFamilyChoices else {
                return model
            }
            // Code discovery accepts only IDs containing `claude` or
            // `anthropic`, then maps canonical family references to its native
            // picker aliases. Context variants would bypass that mapping and
            // survive as separate `From gateway` rows.
            let choice = ClaudeCodeModelChoice(
                route: route, supports1MContext: target.supports1MContext, indicator: snapshot.modelIndicator
            )
            model.displayName = choice.label
            model.description = choice.description
            model.maxInputTokens = target.supports1MContext ? 1_000_000 : 200_000
            return model
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
