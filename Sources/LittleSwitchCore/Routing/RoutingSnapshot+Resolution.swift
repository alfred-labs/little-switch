import Foundation
import LittleSwitchCommon

extension RoutingSnapshot {
    public var validTargets: [String: RoutedTarget] {
        let providersByID = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        let routesByID = Dictionary(uniqueKeysWithValues: ClaudeRoute.all.map { ($0.id, $0) })
        var result: [String: RoutedTarget] = [:]
        for (routeID, mapping) in mappings {
            guard let route = routesByID[routeID],
                let provider = providersByID[mapping.providerID],
                provider.models.contains(where: { $0.id == mapping.modelID })
            else {
                continue
            }
            result[routeID] = RoutedTarget(
                route: route,
                provider: provider,
                modelID: mapping.modelID
            )
        }
        return result
    }

    public var hasValidMapping: Bool {
        !validTargets.isEmpty
    }

    public var validCodexTargets: [String: CodexModelTarget] {
        let exposed = codex.exposedModels(in: providers)
        var targets = Dictionary(
            uniqueKeysWithValues: exposed.map {
                (CodexCatalog.slug(for: $0), $0)
            }
        )
        if let target = codex.resolvedAutoReviewTarget(in: providers) {
            targets[CodexCatalog.managedAutoReviewModel] = target
        }
        return targets
    }

    public func resolveCodex(model: String) -> CodexModelTarget? {
        validCodexTargets[model]
    }

    public func resolve(model: String) -> RoutedTarget? {
        let suffix = "[1m]"
        let usesExtendedContext = model.hasSuffix(suffix)
        let baseModel = usesExtendedContext ? String(model.dropLast(suffix.count)) : model
        guard !baseModel.isEmpty, !baseModel.hasSuffix(suffix) else {
            return nil
        }

        let targets = validTargets
        let target =
            targets[baseModel]
            ?? ClaudeRoute.all.lazy
            .compactMap { targets[$0.id] }
            .first { target in
                // Advertised catalog names must stay resolvable: a client
                // echoing a served `display_name` reaches its route.
                target.reference == baseModel
                    || target.route.catalogDisplayName(indicator: modelIndicator)
                        == baseModel
            }
        guard let target else {
            return nil
        }
        if usesExtendedContext {
            guard target.supports1MContext else {
                return nil
            }
        }
        return target
    }

    package func providerRequestPoolConfiguration(
        providerRevisions: [UUID: UInt64]
    ) -> ProviderRequestPoolConfiguration {
        var routes: [ProviderRequestRouteKey: ProviderRequestRouteTarget] = [:]
        for (routeID, target) in validTargets {
            routes[
                ProviderRequestRouteKey(client: .claude, modelIdentifier: routeID)
            ] = ProviderRequestRouteTarget(
                providerID: target.provider.id,
                modelID: target.modelID
            )
        }
        for (slug, target) in validCodexTargets {
            routes[
                ProviderRequestRouteKey(client: .codex, modelIdentifier: slug)
            ] = ProviderRequestRouteTarget(
                providerID: target.provider.id,
                modelID: target.model.id
            )
        }
        return ProviderRequestPoolConfiguration(
            providers: providers.map { provider in
                ProviderRequestPoolProviderConfiguration(
                    id: provider.id,
                    displayName: provider.name,
                    maximumParallelRequests: provider.maximumParallelRequests,
                    revision: providerRevisions[provider.id] ?? 0,
                    diagnosticModelIDs: Set(provider.models.map(\.id))
                )
            },
            routes: routes
        )
    }
}
