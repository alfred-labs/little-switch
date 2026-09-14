import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    public func setClaudeCodeDefaultModel(
        _ routeID: String?
    ) async throws -> CoordinatorSnapshot {
        try await setClaudeCodeDefaultModel(
            routeID,
            contextMode: pendingClaudeCodeSettings?.contextMode
                ?? configuration.claudeCode.contextMode
        )
    }

    public func setClaudeCodeDefaultModel(
        _ routeID: String?,
        contextMode: ClaudeCodeContextMode
    ) async throws -> CoordinatorSnapshot {
        if let routeID {
            // Validate against the draft-merged view: the picker offers
            // routes the pending mapping draft adds, so accepting one must
            // stage against the mappings that will exist after Apply, not
            // the applied set the draft replaces.
            let mappedRouteIDs = configuration.claudeCode.mappedRouteIDs(
                providers: draftedMappingConfiguration.providers,
                mappings: draftedMappingConfiguration.mappings
            )
            if !mappedRouteIDs.contains(routeID) {
                throw Error.invalidMapping
            }
        }

        if configuration.claudeCode.connected {
            updateClaudeCodeDraft {
                $0.defaultModel = routeID
                $0.contextMode = contextMode
            }
            return await snapshot()
        }

        let previous = configuration
        configuration.claudeCode.defaultModel = routeID
        configuration.claudeCode.contextMode = contextMode
        configuration.claudeCode = configuration.claudeCode.normalized(
            providers: configuration.providers,
            mappings: configuration.mappings
        )
        do {
            try configurationStore.save(configuration)
        } catch {
            configuration = previous
            throw error
        }
        return await snapshot()
    }

    public func connectClaudeCode() async throws -> CoordinatorSnapshot {
        let profileManager = try claudeCodeDependencies()
        guard claudeCodeStatus != .recoveryAvailable,
            claudeCodeStatus != .recoveryUnavailable
        else {
            throw Error.claudeCodeRecoveryRequired
        }

        var candidate =
            pendingClaudeCodeSettings?.applying(to: configuration)
            ?? configuration
        candidate.claudeCode.connected = true
        candidate.claudeCode = candidate.claudeCode.normalized(
            providers: candidate.providers,
            mappings: candidate.mappings
        )
        let managed = try resolvedClaudeCodeSettings(for: candidate)
        let previous = configuration
        try await startGateway(snapshot: routingSnapshot())

        do {
            try profileManager.activate(managed: managed)
            try configurationStore.save(candidate)
            configuration = candidate
            pendingClaudeCodeSettings = nil
            appliedClaudeCodeSettings = managed
            claudeCodeStatus = .connected
            return await snapshot()
        } catch {
            let restored = (try? profileManager.restore()) != nil
            configuration = previous
            let saved = (try? configurationStore.save(previous)) != nil
            pendingClaudeCodeSettings = nil
            appliedClaudeCodeSettings = nil
            claudeCodeStatus = .disconnected
            guard restored, saved else {
                throw Error.rollbackFailed
            }
            throw error
        }
    }

    public func applyClaudeCode() async throws -> CoordinatorSnapshot {
        guard configuration.claudeCode.connected else {
            return await snapshot()
        }
        let profileManager = try claudeCodeDependencies()
        if claudeCodeStatus == .needsAttention, !hasPendingClaudeCodeChanges {
            let managed = try resolvedClaudeCodeSettings(for: configuration)
            try profileManager.activate(managed: managed)
            appliedClaudeCodeSettings = managed
            claudeCodeStatus = .connected
            return await snapshot()
        }
        guard hasPendingClaudeCodeChanges else {
            return await snapshot()
        }
        let previous = configuration
        let previousManaged = appliedClaudeCodeSettings
        var candidate =
            pendingClaudeCodeSettings?.applying(to: configuration)
            ?? configuration
        candidate.claudeCode.connected = true
        candidate.claudeCode = candidate.claudeCode.normalized(
            providers: candidate.providers,
            mappings: candidate.mappings
        )
        let managed = try resolvedClaudeCodeSettings(for: candidate)

        do {
            try profileManager.activate(managed: managed)
            try configurationStore.save(candidate)
            configuration = candidate
            pendingClaudeCodeSettings = nil
            appliedClaudeCodeSettings = managed
            claudeCodeStatus = .connected
            return await snapshot()
        } catch {
            configuration = previous
            var rollbackSucceeded = (try? configurationStore.save(previous)) != nil
            if let previousManaged {
                if (try? profileManager.activate(managed: previousManaged)) == nil {
                    rollbackSucceeded = false
                }
            } else {
                rollbackSucceeded = false
            }
            appliedClaudeCodeSettings = previousManaged
            claudeCodeStatus = .connected
            guard rollbackSucceeded else {
                throw Error.rollbackFailed
            }
            throw error
        }
    }

    public func disconnectClaudeCode() async throws -> CoordinatorSnapshot {
        return try await restoreClaudeCodeConnection()
    }

    public func restoreClaudeCodeSettings() async throws -> CoordinatorSnapshot {
        try await restoreClaudeCodeConnection()
    }

    package var hasPendingClaudeCodeChanges: Bool {
        guard configuration.claudeCode.connected else {
            return false
        }
        // Presentation reads the drafted view: the mapping draft and the
        // Claude Code draft commit together, so pending-ness compares the
        // settings Apply would write, not the applied mappings they
        // replace.
        let candidate =
            pendingClaudeCodeSettings?.applying(to: draftedMappingConfiguration)
            ?? draftedMappingConfiguration
        guard let managed = try? resolvedClaudeCodeSettings(for: candidate),
            let appliedClaudeCodeSettings
        else {
            return true
        }
        return managed != appliedClaudeCodeSettings
    }

    package func initializeClaudeCodeStatus() throws {
        guard let claudeCodeProfileManager else {
            if configuration.claudeCode.connected {
                configuration.claudeCode.connected = false
                try configurationStore.save(configuration)
                claudeCodeStatus = .recoveryUnavailable
            } else {
                claudeCodeStatus = .disconnected
            }
            appliedClaudeCodeSettings = nil
            return
        }

        let expected = try? resolvedClaudeCodeSettings(for: configuration)
        let profileStatus: ClaudeCodeProfileStatus
        do {
            profileStatus = try claudeCodeProfileManager.status(expected: expected)
        } catch {
            if configuration.claudeCode.connected {
                configuration.claudeCode.connected = false
                try configurationStore.save(configuration)
            }
            appliedClaudeCodeSettings = nil
            claudeCodeStatus = .recoveryUnavailable
            return
        }

        switch (configuration.claudeCode.connected, profileStatus) {
        case (false, .inactive):
            appliedClaudeCodeSettings = nil
            claudeCodeStatus = .disconnected
        case (false, .active), (false, .drifted):
            appliedClaudeCodeSettings = nil
            claudeCodeStatus = .recoveryAvailable
        case (true, .active):
            appliedClaudeCodeSettings = expected
            claudeCodeStatus = expected == nil ? .needsAttention : .connected
        case (true, .drifted):
            appliedClaudeCodeSettings = expected
            claudeCodeStatus = .needsAttention
        case (true, .inactive):
            configuration.claudeCode.connected = false
            try configurationStore.save(configuration)
            appliedClaudeCodeSettings = nil
            claudeCodeStatus = .recoveryUnavailable
        }
    }

    package func normalizeClaudeCodeConfiguration() {
        configuration.claudeCode = configuration.claudeCode.normalized(
            providers: configuration.providers,
            mappings: configuration.mappings
        )
        reconcileClaudeCodeDraft()
    }

    private func restoreClaudeCodeConnection() async throws -> CoordinatorSnapshot {
        let profileManager = try claudeCodeDependencies()
        let previous = configuration
        var disconnected = configuration
        disconnected.claudeCode.connected = false
        try configurationStore.save(disconnected)
        configuration = disconnected

        do {
            try profileManager.restore()
        } catch {
            configuration = previous
            guard (try? configurationStore.save(previous)) != nil else {
                throw Error.rollbackFailed
            }
            claudeCodeStatus =
                previous.claudeCode.connected
                ? .connected
                : .recoveryAvailable
            throw error
        }

        pendingClaudeCodeSettings = nil
        appliedClaudeCodeSettings = nil
        claudeCodeStatus = .disconnected
        return await snapshot()
    }

    private func resolvedClaudeCodeSettings(
        for configuration: AppConfiguration
    ) throws -> ClaudeCodeManagedSettings {
        do {
            return try ClaudeCodeManagedSettings.resolve(
                providers: configuration.providers,
                mappings: configuration.mappings,
                configuration: configuration.claudeCode,
                tlsEnabled: tlsProvisioner.map {
                    $0.isTrusted(secretStore: secretStore)
                } ?? false
            )
        } catch ClaudeCodeManagedSettings.Error.noMappedModel {
            throw Error.noMappedClaudeCodeModel
        }
    }

    private func claudeCodeDependencies() throws -> any ClaudeCodeProfileManaging {
        guard let claudeCodeProfileManager else {
            throw Error.claudeCodeUnavailable
        }
        return claudeCodeProfileManager
    }
}

extension ApplicationCoordinator {
    package func reconcileClaudeCodeDraft() {
        guard let pendingClaudeCodeSettings else {
            return
        }
        let base = draftedMappingConfiguration
        let reconciled = pendingClaudeCodeSettings.reconciled(with: base)
        self.pendingClaudeCodeSettings =
            reconciled == ClaudeCodeSettingsDraft(configuration: base)
            ? nil
            : reconciled
    }

    package func updateClaudeCodeDraft(
        _ change: (inout ClaudeCodeSettingsDraft) -> Void
    ) {
        let base = draftedMappingConfiguration
        var draft =
            pendingClaudeCodeSettings
            ?? ClaudeCodeSettingsDraft(configuration: base)
        change(&draft)
        let reconciled = draft.reconciled(with: base)
        pendingClaudeCodeSettings =
            reconciled == ClaudeCodeSettingsDraft(configuration: base)
            ? nil
            : reconciled
    }
}
