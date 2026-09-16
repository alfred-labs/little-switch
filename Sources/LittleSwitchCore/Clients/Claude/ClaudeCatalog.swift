import Foundation
import LittleSwitchCommon

public enum ClaudeCatalog {
    package enum ContextPresentation: Equatable, Sendable {
        case capabilities
        case explicitChoices
    }

    package static func make(
        from snapshot: RoutingSnapshot,
        contextPresentation: ContextPresentation = .capabilities
    ) -> ClaudeCatalogResponse {
        let targets = snapshot.validTargets
        let models = ClaudeRoute.all.flatMap { route -> [ClaudeCatalogModel] in
            guard let target = targets[route.id] else {
                return []
            }
            let standard = ClaudeCatalogModel(
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
            guard contextPresentation == .explicitChoices, target.supports1MContext else {
                return [standard]
            }
            // Claude Code discovery retains IDs and labels but discards
            // supports_1m. Publish the selectable reference explicitly.
            var extended = standard
            extended.id += "[1m]"
            extended.displayName = route.catalogDisplayName(indicator: snapshot.modelIndicator, extendedContext: true)
            extended.maxInputTokens = 1_000_000
            extended.supports1M = false
            extended.isFamilyDefault = false
            return [standard, extended]
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
