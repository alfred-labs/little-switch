import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    public func setCodexAutoReviewModel(
        _ mapping: ModelMapping?
    ) async throws -> CoordinatorSnapshot {
        let available = configuration.codex.availableModels(in: configuration.providers)
        if let mapping, !available.contains(where: { $0.mapping == mapping }) {
            throw Error.invalidMapping
        }
        if configuration.codex.connected {
            updateCodexDraft { $0.autoReviewModel = mapping }
            return await snapshot()
        }

        let previous = configuration
        configuration.codex.autoReviewModel = mapping
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
