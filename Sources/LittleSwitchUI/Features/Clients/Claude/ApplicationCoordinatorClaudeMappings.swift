import Foundation
import LittleSwitchCore

/// The connected mapping draft: edits wait here until Apply commits them in
/// one persist and one gateway routing swap. Split from the provider files
/// to hold the draft lifecycle next to its normalization rules.
extension ApplicationCoordinator {
    /// Commits the mapping draft: one save, one gateway routing swap. The
    /// live-routing safety rule carries over from single edits — a connected
    /// apply may not strand clients on an empty catalog.
    public func applyClaudeMappings() async throws -> CoordinatorSnapshot {
        guard let draft = pendingClaudeMappings else {
            return await snapshot()
        }
        if configuration.connected {
            let candidate = RoutingSnapshot(
                generation: 0,
                providers: configuration.providers,
                mappings: draft
            )
            guard candidate.hasValidMapping else {
                throw Error.noMappedModel
            }
        }

        let previous = configuration
        // Normalization ahead of the save reconciles the Claude Code draft
        // against the candidate mappings and may drop it entirely; a failed
        // save must give both drafts back exactly as they were staged.
        let previousClaudeCodeDraft = pendingClaudeCodeSettings
        configuration.mappings = draft
        normalizeClaudeCodeConfiguration()
        do {
            try configurationStore.save(configuration)
        } catch {
            configuration = previous
            pendingClaudeCodeSettings = previousClaudeCodeDraft
            throw error
        }
        pendingClaudeMappings = nil
        await replaceGatewayRoutingIfNeeded()
        return await snapshot()
    }

    package var hasPendingClaudeMappings: Bool {
        pendingClaudeMappings != nil
    }

    package func updateClaudeMappingsDraft(
        _ change: (inout [String: ModelMapping]) -> Void
    ) {
        var draft = pendingClaudeMappings ?? configuration.mappings
        change(&draft)
        pendingClaudeMappings = normalizedClaudeMappingsDraft(draft)
    }

    package func reconcileClaudeMappingsDraft() {
        guard let pendingClaudeMappings else {
            return
        }
        self.pendingClaudeMappings = normalizedClaudeMappingsDraft(pendingClaudeMappings)
    }

    /// Drops draft entries whose provider or model vanished, and nils the
    /// draft back out when what remains equals the applied mappings.
    private func normalizedClaudeMappingsDraft(
        _ draft: [String: ModelMapping]
    ) -> [String: ModelMapping]? {
        let reconciled = draft.filter { _, mapping in isAvailableMapping(mapping) }
        return reconciled == configuration.mappings ? nil : reconciled
    }

    /// The configuration the application drafts reconcile against: the
    /// applied state with the pending Claude mappings merged in, so a
    /// Claude Code default may target a route the mapping draft adds and
    /// every draft describes the state Apply will actually commit.
    package var draftedMappingConfiguration: AppConfiguration {
        var drafted = configuration
        if let pendingClaudeMappings {
            drafted.mappings = pendingClaudeMappings
        }
        return drafted
    }

    private func isAvailableMapping(_ mapping: ModelMapping) -> Bool {
        configuration.providers.contains { provider in
            provider.id == mapping.providerID
                && provider.models.contains { $0.id == mapping.modelID }
        }
    }
}
