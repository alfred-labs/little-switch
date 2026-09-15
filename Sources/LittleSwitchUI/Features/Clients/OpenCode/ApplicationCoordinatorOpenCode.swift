import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    public func setOpenCodeDefaultModel(
        _ mapping: ModelMapping?
    ) async throws -> CoordinatorSnapshot {
        if let mapping, !isAvailableOpenCodeMapping(mapping) {
            throw Error.invalidMapping
        }
        if configuration.openCode.connected {
            updateOpenCodeDraft { $0.defaultModel = mapping }
            return await snapshot()
        }

        let previous = configuration
        configuration.openCode.defaultModel = mapping
        configuration.openCode = configuration.openCode.normalized(
            providers: configuration.providers,
            codex: configuration.codex
        )
        do {
            try configurationStore.save(configuration)
        } catch {
            configuration = previous
            throw error
        }
        return await snapshot()
    }

    public func connectOpenCode() async throws -> CoordinatorSnapshot {
        _ = await responsesWireVerdicts()
        let profileManager = try openCodeDependency()
        guard openCodeStatus != .recoveryAvailable,
            openCodeStatus != .recoveryUnavailable
        else {
            throw Error.openCodeRecoveryRequired
        }
        guard pendingCodexSettings == nil else {
            throw Error.codexApplyRequiredForOpenCode
        }

        var candidate = pendingOpenCodeSettings?.applying(to: configuration) ?? configuration
        candidate.openCode.connected = true
        candidate.openCode = candidate.openCode.normalized(
            providers: candidate.providers,
            codex: candidate.codex
        )
        let managed = try resolvedOpenCodeSettings(for: candidate)
        let previous = configuration
        try await startGateway(snapshot: routingSnapshot())

        do {
            try profileManager.activate(managed: managed)
            candidate = retainingCurrentImageObservations(in: candidate)
            try configurationStore.save(candidate)
            configuration = candidate
            pendingOpenCodeSettings = nil
            appliedOpenCodeSettings = managed
            openCodeStatus = .connected
            return await snapshot()
        } catch {
            let restored = (try? profileManager.restore()) != nil
            configuration = retainingCurrentImageObservations(in: previous)
            let saved = (try? configurationStore.save(configuration)) != nil
            pendingOpenCodeSettings = nil
            appliedOpenCodeSettings = nil
            openCodeStatus = .disconnected
            guard restored, saved else {
                throw Error.rollbackFailed
            }
            throw error
        }
    }

    public func applyOpenCode() async throws -> CoordinatorSnapshot {
        _ = await responsesWireVerdicts()
        guard configuration.openCode.connected, hasPendingOpenCodeChanges else {
            return await snapshot()
        }
        guard pendingCodexSettings == nil else {
            throw Error.codexApplyRequiredForOpenCode
        }
        let profileManager = try openCodeDependency()
        var candidate = pendingOpenCodeSettings?.applying(to: configuration) ?? configuration
        candidate.openCode.connected = true
        candidate.openCode = candidate.openCode.normalized(
            providers: candidate.providers,
            codex: candidate.codex
        )
        let managed = try resolvedOpenCodeSettings(for: candidate)

        do {
            try profileManager.activate(managed: managed) {
                try configurationStore.save(candidate)
            }
        } catch OpenCodeProfileManager.Error.rollbackFailed {
            throw Error.rollbackFailed
        }
        configuration = candidate
        pendingOpenCodeSettings = nil
        appliedOpenCodeSettings = managed
        openCodeStatus = .connected
        return await snapshot()
    }

    public func disconnectOpenCode() async throws -> CoordinatorSnapshot {
        try await restoreOpenCodeConnection()
    }

    public func restoreOpenCodeSettings() async throws -> CoordinatorSnapshot {
        try await restoreOpenCodeConnection()
    }

    package var hasPendingOpenCodeChanges: Bool {
        guard configuration.openCode.connected else {
            return false
        }
        if pendingCodexSettings != nil || openCodeStatus == .needsAttention {
            return true
        }
        let candidate = pendingOpenCodeSettings?.applying(to: configuration) ?? configuration
        guard let managed = try? resolvedOpenCodeSettings(for: candidate),
            let appliedOpenCodeSettings
        else {
            return true
        }
        return managed != appliedOpenCodeSettings
    }

    package func initializeOpenCodeStatus() throws {
        guard let openCodeProfileManager else {
            if configuration.openCode.connected {
                configuration.openCode.connected = false
                try configurationStore.save(configuration)
                openCodeStatus = .recoveryUnavailable
            } else {
                openCodeStatus = .disconnected
            }
            appliedOpenCodeSettings = nil
            return
        }

        let expected = try? resolvedOpenCodeSettings(for: configuration)
        let profileStatus: OpenCodeProfileStatus
        let recordedManaged: OpenCodeManagedSettings?
        do {
            profileStatus = try openCodeProfileManager.status(expected: expected)
            recordedManaged =
                profileStatus == .drifted
                ? try openCodeProfileManager.managedSettings()
                : expected
        } catch {
            if configuration.openCode.connected {
                configuration.openCode.connected = false
                try configurationStore.save(configuration)
            }
            appliedOpenCodeSettings = nil
            openCodeStatus = .recoveryUnavailable
            return
        }

        switch (configuration.openCode.connected, profileStatus) {
        case (false, .inactive):
            appliedOpenCodeSettings = nil
            openCodeStatus = .disconnected
        case (false, .active), (false, .drifted):
            appliedOpenCodeSettings = nil
            openCodeStatus = .recoveryAvailable
        case (true, .active):
            appliedOpenCodeSettings = expected
            openCodeStatus = expected == nil ? .needsAttention : .connected
        case (true, .drifted):
            appliedOpenCodeSettings = recordedManaged
            openCodeStatus = .needsAttention
        case (true, .inactive):
            configuration.openCode.connected = false
            try configurationStore.save(configuration)
            appliedOpenCodeSettings = nil
            openCodeStatus = .recoveryUnavailable
        }
    }

    package func normalizeOpenCodeConfiguration() {
        if configuration.openCode.connected {
            reconcileOpenCodeDraft()
        } else {
            configuration.openCode = configuration.openCode.normalized(
                providers: configuration.providers,
                codex: configuration.codex
            )
            pendingOpenCodeSettings = nil
        }
    }

    package func reconcileOpenCodeDraft() {
        guard configuration.openCode.connected else {
            pendingOpenCodeSettings = nil
            return
        }
        var effectiveConfiguration =
            pendingCodexSettings?.applying(to: configuration)
            ?? configuration
        effectiveConfiguration.openCode = effectiveConfiguration.openCode.normalized(
            providers: effectiveConfiguration.providers,
            codex: effectiveConfiguration.codex
        )
        let draft =
            pendingOpenCodeSettings
            ?? OpenCodeSettingsDraft(configuration: configuration)
        let reconciled = draft.reconciled(with: effectiveConfiguration)
        pendingOpenCodeSettings =
            reconciled == OpenCodeSettingsDraft(configuration: configuration)
            ? nil
            : reconciled
    }

    private func updateOpenCodeDraft(
        _ change: (inout OpenCodeSettingsDraft) -> Void
    ) {
        var draft =
            pendingOpenCodeSettings
            ?? OpenCodeSettingsDraft(configuration: configuration)
        change(&draft)
        pendingOpenCodeSettings = draft
        reconcileOpenCodeDraft()
    }

    private func restoreOpenCodeConnection() async throws -> CoordinatorSnapshot {
        let profileManager = try openCodeDependency()
        let previous = configuration
        var disconnected = configuration
        disconnected.openCode.connected = false
        try configurationStore.save(disconnected)
        configuration = disconnected

        do {
            try profileManager.restore()
        } catch {
            configuration = previous
            guard (try? configurationStore.save(previous)) != nil else {
                throw Error.rollbackFailed
            }
            openCodeStatus =
                previous.openCode.connected
                ? .connected
                : .recoveryAvailable
            throw error
        }

        pendingOpenCodeSettings = nil
        appliedOpenCodeSettings = nil
        openCodeStatus = .disconnected
        return await snapshot()
    }

    private func resolvedOpenCodeSettings(
        for configuration: AppConfiguration
    ) throws -> OpenCodeManagedSettings {
        do {
            return try OpenCodeManagedSettings.resolve(
                providers: configuration.providers,
                codex: configuration.codex,
                configuration: configuration.openCode,
                responsesWireVerdicts: catalogResponsesWireVerdicts
            )
        } catch OpenCodeManagedSettings.Error.noExposedModel {
            throw Error.noExposedOpenCodeModel
        }
    }

    private func openCodeDependency() throws -> any OpenCodeProfileManaging {
        guard let openCodeProfileManager else {
            throw Error.openCodeUnavailable
        }
        return openCodeProfileManager
    }

    private func isAvailableOpenCodeMapping(_ mapping: ModelMapping) -> Bool {
        configuration.codex.exposedModels(in: configuration.providers)
            .contains { $0.mapping == mapping }
    }
}
