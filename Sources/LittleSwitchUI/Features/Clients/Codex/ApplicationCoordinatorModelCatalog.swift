import LittleSwitchCore

extension ApplicationCoordinator {
    /// One catalog action, one transaction. A filtered selection only includes
    /// visible mappings; the current default always stays available.
    public func setCodexModelsExposure(
        _ mappings: [ModelMapping],
        exposed: Bool
    ) async throws -> CoordinatorSnapshot {
        let available = Set(
            configuration.providers.flatMap { provider in
                provider.models.map { ModelMapping(providerID: provider.id, modelID: $0.id) }
            })
        guard mappings.allSatisfy({ available.contains($0) }) else { throw Error.invalidMapping }
        guard !mappings.isEmpty else { return await snapshot() }

        var draft = pendingCodexSettings ?? CodexSettingsDraft(configuration: configuration)
        let targets = Set(mappings).subtracting(draft.defaultModel.map { [$0] } ?? [])
        if exposed {
            draft.excludedModels.removeAll { targets.contains($0) }
        } else {
            // Catalog order is stable even if the caller supplies duplicates.
            for provider in configuration.providers {
                for model in provider.models {
                    let mapping = ModelMapping(providerID: provider.id, modelID: model.id)
                    if targets.contains(mapping), !draft.excludedModels.contains(mapping) {
                        draft.excludedModels.append(mapping)
                    }
                }
            }
        }
        if configuration.codex.connected {
            updateCodexDraft { $0 = draft }
            return await snapshot()
        }
        let previous = configuration
        configuration = draft.applying(to: configuration)
        normalizeOpenCodeConfiguration()
        do {
            try configurationStore.save(configuration)
        } catch {
            configuration = previous
            throw error
        }
        await replaceGatewayRoutingIfNeeded()
        return await snapshot()
    }
}
