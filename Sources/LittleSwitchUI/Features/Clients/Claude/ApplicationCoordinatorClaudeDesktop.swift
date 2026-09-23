import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    package var hasPendingClaudeDesktopChanges: Bool {
        configuration.connected
            && appliedClaudeDesktopCatalog != claudeDesktopCatalog(in: draftedMappingConfiguration)
    }

    package func claudeDesktopCatalog(in configuration: AppConfiguration) -> [ClaudeCodeModelChoice] {
        ClaudeCodeModelChoice.available(
            providers: configuration.providers,
            mappings: configuration.mappings,
            indicator: configuration.modelIndicator
        )
    }

    /// Desktop caches its model list for the process lifetime. Routing changes
    /// stay live; only this explicit action reloads the presentation catalog.
    public func applyClaudeDesktop() async throws -> CoordinatorSnapshot {
        guard !claudeDesktopApplyInProgress else { throw CancellationError() }
        claudeDesktopApplyInProgress = true
        defer { claudeDesktopApplyInProgress = false }
        let generation = claudeDesktopLifecycleGeneration
        try await requireUnmanagedClaudeDesktop()
        try requireCurrentClaudeDesktopAction(generation)
        guard configuration.connected else { return await snapshot() }
        try requireOwnedClaudeDesktopCatalog()
        guard appliedClaudeDesktopCatalog != claudeDesktopCatalog(in: configuration) else {
            return await snapshot()
        }

        let wasRunning = await claudeController.isRunning()
        try requireCurrentClaudeDesktopAction(generation)
        if wasRunning {
            // A refused quit must not leave an on-disk profile newer than the
            // catalog the running process is still using.
            try await claudeController.quitAndWait()
        }
        let catalog: [ClaudeCodeModelChoice]
        do {
            try await requireUnmanagedClaudeDesktop()
            try requireCurrentClaudeDesktopAction(generation)
            // Quit may suspend while discovery or another intent changes state.
            // Recheck ownership and derive from current, committed routing.
            try requireOwnedClaudeDesktopCatalog()
            catalog = claudeDesktopCatalog(in: configuration)
            try profileManager.updateCatalog(catalog, autoMode: configuration.autoMode)
        } catch {
            if error as? ClaudeProfileManager.Error == .rollbackFailed {
                // Compensation could not establish which catalog remains on disk.
                appliedClaudeDesktopCatalog = nil
            }
            try? await reopenClaudeDesktopAfterFailure(wasRunning: wasRunning, generation: generation)
            if error as? ClaudeProfileManager.Error == .inactiveProfile {
                throw Error.claudeDesktopProfileChanged
            }
            throw error
        }

        // Keep Apply available if reopening fails, even though the file is now
        // correct. A retry with Desktop stopped can settle without launching it.
        appliedClaudeDesktopCatalog = nil
        if wasRunning { try await claudeController.open() }
        try requireCurrentClaudeDesktopAction(generation)
        appliedClaudeDesktopCatalog = catalog
        return await snapshot()
    }

    private func reopenClaudeDesktopAfterFailure(wasRunning: Bool, generation: UInt64) async throws {
        guard wasRunning, configuration.connected, generation == claudeDesktopLifecycleGeneration else { return }
        try await requireUnmanagedClaudeDesktop()
        try requireCurrentClaudeDesktopAction(generation)
        try await claudeController.open()
    }

    private func requireCurrentClaudeDesktopAction(_ generation: UInt64) throws {
        try Task.checkCancellation()
        guard !isShuttingDown, generation == claudeDesktopLifecycleGeneration else { throw CancellationError() }
    }

    private func requireOwnedClaudeDesktopCatalog() throws {
        guard configuration.connected,
            try profileManager.isActive(autoMode: configuration.autoMode)
        else { throw Error.claudeDesktopProfileChanged }
        guard routingSnapshot().hasValidMapping else { throw Error.noMappedModel }
    }
}
