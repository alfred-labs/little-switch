import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    /// Hot-swap catalog labels and update the applied CLI presentation without
    /// applying pending routing/default changes or restarting either client.
    public func setModelIndicator(_ indicator: ModelIndicator) async throws -> CoordinatorSnapshot {
        let previous = configuration
        let previousManaged = appliedClaudeCodeSettings
        var candidate = configuration
        candidate.modelIndicator = indicator
        var attemptedProfile: (any ClaudeCodeProfileManaging)?

        do {
            try configurationStore.save(candidate)
            if configuration.claudeCode.connected, claudeCodeStatus == .connected, let previousManaged {
                let updated = previousManaged.withModelIndicator(indicator)
                if updated != previousManaged {
                    let manager = try claudeCodeDependencies()
                    // At startup a drifted profile may carry an expected,
                    // not actually applied, signature. Never migrate it or
                    // overwrite external edits from a cosmetic preference.
                    if try manager.status(expected: previousManaged) == .active {
                        attemptedProfile = manager
                        try manager.activate(managed: updated)
                        appliedClaudeCodeSettings = updated
                    } else {
                        claudeCodeStatus = .needsAttention
                    }
                }
            }
            configuration = candidate
        } catch {
            let configurationRestored = (try? configurationStore.save(previous)) != nil
            var profileRestored = true
            if let attemptedProfile, let previousManaged {
                profileRestored = (try? attemptedProfile.activate(managed: previousManaged)) != nil
            }
            appliedClaudeCodeSettings = previousManaged
            guard configurationRestored, profileRestored else {
                claudeCodeStatus = .needsAttention
                throw Error.rollbackFailed
            }
            throw error
        }

        // Reapplying the same preference also repairs a drifted gateway.
        await replaceGatewayRoutingIfNeeded()
        return await snapshot()
    }
}
