import Foundation
import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    /// Context overrides ride along an edit; a fresh discovery otherwise
    /// starts clean.
    package func discoveredModels(
        provider: Provider,
        input: ProviderInput,
        previousProvider: Provider?
    ) throws -> [DiscoveredModel] {
        let contextOverrides = input.contextOverrides ?? existingContextOverrides(previousProvider)
        return try applyingContextOverrides(contextOverrides, to: provider.models)
    }

    package func existingContextOverrides(_ provider: Provider?) -> [String: Int] {
        guard let provider else {
            return [:]
        }
        return provider.models.reduce(into: [:]) { overrides, model in
            if model.allows1MContextOverride, let value = model.contextWindowOverride {
                overrides[model.id] = value
            }
        }
    }

    package func applyingContextOverrides(
        _ overrides: [String: Int],
        to models: [DiscoveredModel]
    ) throws -> [DiscoveredModel] {
        let modelIDs = Set(models.map(\.id))
        guard overrides.allSatisfy({ modelIDs.contains($0.key) && $0.value > 0 }) else {
            throw Error.invalidModelContext
        }
        return models.map { model in
            var updated = model
            // Discovery replaces manual declarations, including redundant 1M
            // values. Later missing metadata must not resurrect an old override.
            updated.contextWindowOverride = model.allows1MContextOverride ? overrides[model.id] : nil
            return updated
        }
    }
}
