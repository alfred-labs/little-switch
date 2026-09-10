import LittleSwitchCore

package struct AppliedCodexSnapshot: Sendable {
    let configuration: CodexConfiguration
    let providers: [Provider]
    let signature: CodexManagedProfileSignature
}

package enum AppliedCodexState: Sendable {
    case disconnected
    case connected(AppliedCodexSnapshot)
}

extension ApplicationCoordinator {
    public func setCodexDefaultModel(
        _ mapping: ModelMapping?
    ) async throws -> CoordinatorSnapshot {
        if let mapping, !isAvailableCodexMapping(mapping) {
            throw Error.invalidMapping
        }
        if configuration.codex.connected {
            updateCodexDraft { $0.defaultModel = mapping }
            return await snapshot()
        }

        let previous = configuration
        configuration.codex.defaultModel = mapping
        configuration.codex = configuration.codex.normalized(for: configuration.providers)
        do {
            try configurationStore.save(configuration)
        } catch {
            configuration = previous
            throw error
        }
        await replaceGatewayRoutingIfNeeded()
        return await snapshot()
    }

    public func connectCodex() async throws -> CoordinatorSnapshot {
        let profileManager = try codexProfileDependency()
        var candidate = pendingCodexSettings?.applying(to: configuration) ?? configuration
        candidate.codex.connected = true
        candidate.codex = candidate.codex.normalized(for: candidate.providers)
        guard !candidate.codex.exposedModels(in: candidate.providers).isEmpty else {
            throw Error.noExposedCodexModel
        }
        let signature = try CodexManagedProfileSignature.resolve(
            providers: candidate.providers,
            configuration: candidate.codex
        )

        let previous = configuration
        try await startGateway(snapshot: routingSnapshot(for: candidate))
        do {
            try profileManager.activate(
                providers: candidate.providers,
                configuration: candidate.codex,
                signature: signature
            )
            await replaceGatewayRouting(with: candidate)
            try configurationStore.save(candidate)
            configuration = candidate
            pendingCodexSettings = nil
            appliedCodexState = .connected(
                AppliedCodexSnapshot(
                    configuration: candidate.codex,
                    providers: candidate.providers,
                    signature: signature
                )
            )
            reconcileOpenCodeDraft()
            await relaunchCodexApplyingDesktopState()
            return await snapshot()
        } catch {
            let rollbackSucceeded = await rollbackCodexApply(
                to: previous,
                appliedState: .disconnected,
                profileManager: profileManager
            )
            guard rollbackSucceeded else {
                throw Error.rollbackFailed
            }
            throw error
        }
    }

    public func applyCodexSettings() async throws -> CoordinatorSnapshot {
        guard configuration.codex.connected, hasPendingCodexChanges else {
            return await snapshot()
        }
        let profileManager = try codexProfileDependency()
        var candidate = pendingCodexSettings?.applying(to: configuration) ?? configuration
        candidate.codex.connected = true
        candidate.codex = candidate.codex.normalized(for: candidate.providers)
        guard !candidate.codex.exposedModels(in: candidate.providers).isEmpty else {
            throw Error.noExposedCodexModel
        }
        let signature = try CodexManagedProfileSignature.resolve(
            providers: candidate.providers,
            configuration: candidate.codex
        )

        let previous = configuration
        let previousAppliedState = appliedCodexState

        do {
            try profileManager.activate(
                providers: candidate.providers,
                configuration: candidate.codex,
                signature: signature
            )
            await replaceGatewayRouting(with: candidate)
            try configurationStore.save(candidate)
            configuration = candidate
            pendingCodexSettings = nil
            appliedCodexState = .connected(
                AppliedCodexSnapshot(
                    configuration: candidate.codex,
                    providers: candidate.providers,
                    signature: signature
                )
            )
            reconcileOpenCodeDraft()
            await relaunchCodexApplyingDesktopState()
            return await snapshot()
        } catch {
            let rollbackSucceeded = await rollbackCodexApply(
                to: previous,
                appliedState: previousAppliedState,
                profileManager: profileManager
            )
            guard rollbackSucceeded else {
                throw Error.rollbackFailed
            }
            throw error
        }
    }

    public func disconnectCodex() async throws -> CoordinatorSnapshot {
        let profileManager = try codexProfileDependency()

        let previous = configuration
        let previousAppliedState = appliedCodexState
        do {
            try profileManager.restore()
            configuration.codex.connected = false
            try configurationStore.save(configuration)
            await replaceGatewayRoutingIfNeeded()
            pendingCodexSettings = nil
            appliedCodexState = .disconnected
            await relaunchCodexApplyingDesktopState()
            return await snapshot()
        } catch {
            let rollbackSucceeded = await rollbackCodexApply(
                to: previous,
                appliedState: previousAppliedState,
                profileManager: profileManager
            )
            guard rollbackSucceeded else {
                throw Error.rollbackFailed
            }
            throw error
        }
    }

    private func codexProfileDependency() throws -> any CodexProfileManaging {
        guard let codexProfileManager else {
            throw Error.codexUnavailable
        }
        return codexProfileManager
    }

    private func relaunchCodexApplyingDesktopState() async {
        guard let controller = codexController else { return }
        guard await controller.isRunning() else { return }
        do {
            try await controller.quitAndWait()
        } catch {
            return
        }
        try? codexProfileManager?.enableDesktopMaximumEffort()
        _ = try? await controller.open()
    }

    private func isAvailableCodexMapping(_ mapping: ModelMapping) -> Bool {
        configuration.providers.contains { provider in
            provider.id == mapping.providerID
                && provider.models.contains { $0.id == mapping.modelID }
        }
    }

    private func routingSnapshot(for configuration: AppConfiguration) -> RoutingSnapshot {
        RoutingSnapshot(
            generation: 0,
            providers: configuration.providers,
            mappings: configuration.mappings,
            codex: configuration.codex,
            webSearch: configuration.webSearch,
            modelIndicator: configuration.modelIndicator
        )
    }

    private func replaceGatewayRouting(with configuration: AppConfiguration) async {
        await gatewayState?.replace(
            providers: configuration.providers,
            mappings: configuration.mappings,
            codex: configuration.codex,
            webSearch: configuration.webSearch,
            modelIndicator: configuration.modelIndicator
        )
    }

    private func rollbackCodexApply(
        to previous: AppConfiguration,
        appliedState: AppliedCodexState,
        profileManager: any CodexProfileManaging
    ) async -> Bool {
        var succeeded = true
        configuration = previous
        do {
            try configurationStore.save(previous)
        } catch {
            succeeded = false
        }
        await replaceGatewayRouting(with: previous)
        do {
            switch appliedState {
            case .disconnected:
                try profileManager.restore()
            case .connected(let snapshot):
                try profileManager.activate(
                    providers: snapshot.providers,
                    configuration: snapshot.configuration,
                    signature: snapshot.signature
                )
            }
        } catch {
            succeeded = false
        }
        return succeeded
    }

}

extension ApplicationCoordinator {
    package func reconcileCodexDraft() {
        guard let pendingCodexSettings else {
            return
        }
        self.pendingCodexSettings = normalizedCodexDraft(pendingCodexSettings)
    }

    package func updateCodexDraft(
        _ change: (inout CodexSettingsDraft) -> Void
    ) {
        var draft = pendingCodexSettings ?? CodexSettingsDraft(configuration: configuration)
        change(&draft)
        pendingCodexSettings = normalizedCodexDraft(draft)
    }

    package var hasPendingCodexChanges: Bool {
        guard configuration.codex.connected else {
            return false
        }
        if pendingCodexSettings != nil {
            return true
        }
        guard case .connected(let appliedSnapshot) = appliedCodexState else {
            return true
        }
        let currentSignature = try? CodexManagedProfileSignature.resolve(
            providers: configuration.providers,
            configuration: configuration.codex
        )
        return currentSignature != appliedSnapshot.signature
    }

    private func normalizedCodexDraft(
        _ draft: CodexSettingsDraft
    ) -> CodexSettingsDraft? {
        let reconciled = draft.reconciled(providers: configuration.providers)
        return reconciled == CodexSettingsDraft(configuration: configuration)
            ? nil
            : reconciled
    }
}
