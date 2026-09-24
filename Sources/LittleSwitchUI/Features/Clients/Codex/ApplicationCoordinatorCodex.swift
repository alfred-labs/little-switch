import LittleSwitchCommon
import LittleSwitchCore

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
        try beginCodexDesktopOperation()
        defer { finishCodexDesktopOperation() }
        _ = await responsesWireVerdicts()
        let profileManager = try codexProfileDependency()
        var candidate = pendingCodexSettings?.applying(to: configuration) ?? configuration
        candidate.codex.connected = true
        candidate.codex = candidate.codex.normalized(for: candidate.providers)
        guard !candidate.codex.exposedModels(in: candidate.providers).isEmpty else {
            throw Error.noExposedCodexModel
        }
        let signature = try CodexManagedProfileSignature.resolve(
            providers: candidate.providers,
            configuration: candidate.codex,
            responsesWireVerdicts: catalogResponsesWireVerdicts
        )

        let previous = configuration
        try await startGateway(snapshot: routingSnapshot(for: candidate))
        // Quit before writing: a live Codex Desktop rewrites config.toml
        // from memory on model switches and at quit, which races the
        // activation and stomps the managed profile.
        let shouldRelaunchCodex = try await quitCodexForProfileChange()
        do {
            try profileManager.activate(
                providers: candidate.providers,
                configuration: candidate.codex,
                signature: signature
            )
            await replaceGatewayRouting(with: candidate)
            candidate = retainingCurrentImageObservations(in: candidate)
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
            if shouldRelaunchCodex {
                await openCodexApplyingDesktopState()
            }
            return await snapshot()
        } catch {
            let rollbackSucceeded = await rollbackCodexApply(
                to: previous,
                appliedState: .disconnected,
                profileManager: profileManager
            )
            // The quit already happened; hand the user back a running app
            // reading the rolled-back profile whatever the rollback did.
            if shouldRelaunchCodex {
                await openCodexApplyingDesktopState()
            }
            guard rollbackSucceeded else {
                throw Error.rollbackFailed
            }
            throw error
        }
    }

    public func applyCodexSettings() async throws -> CoordinatorSnapshot {
        try beginCodexDesktopOperation()
        defer { finishCodexDesktopOperation() }
        _ = await responsesWireVerdicts()
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
            configuration: candidate.codex,
            responsesWireVerdicts: catalogResponsesWireVerdicts
        )

        let previous = configuration
        let previousAppliedState = appliedCodexState
        // Same race as connectCodex: quit before the activation write.
        let shouldRelaunchCodex = try await quitCodexForProfileChange()

        do {
            try profileManager.activate(
                providers: candidate.providers,
                configuration: candidate.codex,
                signature: signature
            )
            await replaceGatewayRouting(with: candidate)
            candidate = retainingCurrentImageObservations(in: candidate)
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
            if shouldRelaunchCodex {
                await openCodexApplyingDesktopState()
            }
            return await snapshot()
        } catch {
            let rollbackSucceeded = await rollbackCodexApply(
                to: previous,
                appliedState: previousAppliedState,
                profileManager: profileManager
            )
            // The quit already happened; hand the user back a running app
            // reading the rolled-back profile whatever the rollback did.
            if shouldRelaunchCodex {
                await openCodexApplyingDesktopState()
            }
            guard rollbackSucceeded else {
                throw Error.rollbackFailed
            }
            throw error
        }
    }

    public func disconnectCodex() async throws -> CoordinatorSnapshot {
        try beginCodexDesktopOperation()
        defer { finishCodexDesktopOperation() }
        let profileManager = try codexProfileDependency()

        let previous = configuration
        let previousAppliedState = appliedCodexState
        // Quit before restoring: the app's quit-time config flush would
        // otherwise rewrite the managed profile over the restored one.
        let shouldRelaunchCodex = try await quitCodexForProfileChange()
        do {
            try profileManager.restore()
            configuration.codex.connected = false
            try configurationStore.save(configuration)
            await replaceGatewayRoutingIfNeeded()
            pendingCodexSettings = nil
            appliedCodexState = .disconnected
            if shouldRelaunchCodex {
                await openCodexApplyingDesktopState()
            }
            return await snapshot()
        } catch {
            let rollbackSucceeded = await rollbackCodexApply(
                to: previous,
                appliedState: previousAppliedState,
                profileManager: profileManager
            )
            // The quit already happened; hand the user back a running app
            // reading the rolled-back profile whatever the rollback did.
            if shouldRelaunchCodex {
                await openCodexApplyingDesktopState()
            }
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

    /// Quits a running Codex Desktop before a profile write. A live app
    /// rewrites config.toml from memory on model switches and at quit, so
    /// writing while it runs lets it stomp the managed or restored profile.
    /// Returns whether the app should be reopened afterwards — true only
    /// when it was running and quit cleanly.
    private func quitCodexForProfileChange() async throws -> Bool {
        guard let controller = codexController else { return false }
        guard await controller.isRunning() else { return false }
        // The shared host must have a usable ChatGPT launch before quitting;
        // failed recovery or a changed CA file must leave its current UI open.
        if configuration.chatgpt.connected {
            try await startChatGPTListener(installTrust: false)
        }
        try await controller.quitAndWait()
        if configuration.chatgpt.connected || chatGPTDesktopRestoration.requiresRestoration {
            // Transfer the owed desktop relaunch before shutdown can suppress
            // this transaction's open helper while waiting for it to finish.
            chatGPTDesktopRestoration = .relaunchRequired
        }
        return true
    }

    private func openCodexApplyingDesktopState() async {
        guard !isShuttingDown else { return }
        guard let controller = codexController else { return }
        try? codexProfileManager?.enableDesktopMaximumEffort()
        if configuration.chatgpt.connected {
            do {
                // Profile changes update the existing gateway state. Reuse
                // the immutable launch prepared before quitting the desktop.
                try checkChatGPTOperation()
                try await openManagedChatGPT(using: controller)
                chatGPTStatus = .connected
            } catch { chatGPTStatus = .needsAttention }
        } else {
            do {
                try await controller.open()
                chatGPTManagedLaunchID = nil
                chatGPTDesktopRestoration = .normal
            } catch {}
        }
    }

    private func beginCodexDesktopOperation() throws {
        guard !isShuttingDown else { throw CancellationError() }
        guard chatGPTOperation == nil, !codexDesktopOperationInProgress else {
            throw ChatGPTConnectionError.operationInProgress
        }
        codexDesktopOperationInProgress = true
    }

    private func finishCodexDesktopOperation() {
        codexDesktopOperationInProgress = false
        let waiters = codexDesktopOperationWaiters
        codexDesktopOperationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func waitForCodexDesktopOperation() async {
        guard codexDesktopOperationInProgress else { return }
        await withCheckedContinuation { codexDesktopOperationWaiters.append($0) }
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
        let previous = retainingCurrentImageObservations(in: previous)
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
            configuration: configuration.codex,
            responsesWireVerdicts: catalogResponsesWireVerdicts
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
