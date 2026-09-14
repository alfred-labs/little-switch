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
            if let value = model.contextWindowOverride {
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
            updated.contextWindowOverride = overrides[model.id]
            // A detected window below 1M deactivates a 1M override rather
            // than re-exposing a variant the provider cannot serve.
            let overrideClaims1M = updated.contextWindowOverride.map { $0 >= 1_000_000 } == true
            if !updated.allows1MContextOverride, overrideClaims1M {
                updated.contextWindowOverride = nil
            }
            return updated
        }
    }
}
