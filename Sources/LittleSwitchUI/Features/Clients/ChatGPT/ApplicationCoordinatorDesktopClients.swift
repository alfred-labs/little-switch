import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    private struct DesktopCheckpoint: Sendable {
        let configuration: AppConfiguration
        let applied: AppliedCodexState
        let desktop: ChatGPTDesktopRestorationState
    }

    public func connectDesktopClients() async throws -> CoordinatorSnapshot {
        try await changeDesktopConnection(.connect)
    }

    public func disconnectDesktopClients() async throws -> CoordinatorSnapshot {
        try await changeDesktopConnection(.disconnect)
    }

    private enum DesktopConnectionChange {
        case connect
        case disconnect
    }

    private func changeDesktopConnection(_ change: DesktopConnectionChange) async throws -> CoordinatorSnapshot {
        try beginChatGPTOperation()
        let ownsDesktop =
            configuration.codex.connected || configuration.chatgpt.connected
            || chatGPTDesktopRestoration.requiresRestoration || desktopProfileRestorationRequired
        if change == .disconnect && !ownsDesktop {
            return await snapshot()
        }
        chatGPTStatus = change == .connect ? .connecting : .disconnecting
        let operation = Task {
            switch change {
            case .connect: try await self.connectDesktopClientsTransaction()
            case .disconnect: try await self.disconnectDesktopClientsTransaction()
            }
        }
        chatGPTOperation = operation
        defer { chatGPTOperation = nil }
        try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
        return await snapshot()
    }

    private func connectDesktopClientsTransaction() async throws {
        let previous = configuration
        let previousApplied = appliedCodexState
        let previousDesktop = chatGPTDesktopRestoration
        var quit = DesktopQuitState.untouched
        var profileAttempted = false
        do {
            guard let controller = codexController, let profileManager = codexProfileManager else {
                throw ChatGPTConnectionError.unavailable
            }
            _ = await responsesWireVerdicts()
            var candidate = pendingCodexSettings?.applying(to: configuration) ?? configuration
            candidate = applyingChatGPTDraft(to: candidate)
            guard candidate.chatgpt.resolvedModel(in: candidate.providers) != nil else {
                throw ChatGPTConnectionError.noModels
            }
            candidate.codex.connected = true
            candidate.chatgpt.connected = true
            candidate.codex = candidate.codex.normalized(for: candidate.providers)
            guard !candidate.codex.exposedModels(in: candidate.providers).isEmpty else {
                throw Error.noExposedCodexModel
            }
            let signature = try CodexManagedProfileSignature.resolve(
                providers: candidate.providers,
                configuration: candidate.codex,
                responsesWireVerdicts: catalogResponsesWireVerdicts
            )
            _ = try ChatGPTLaunchEnvironment.connected(inheriting: inheritedEnvironment)
            try await startGateway(snapshot: routingSnapshot())
            try checkChatGPTOperation()
            try await startChatGPTListener(installTrust: true)
            try checkChatGPTOperation()
            try validateDesktopSettings(unchangedSince: previous)
            quit = .requested
            try await controller.quitAndWait()
            quit = .completed
            chatGPTDesktopRestoration = .relaunchRequired
            try checkChatGPTOperation()
            try validateDesktopSettings(unchangedSince: previous)
            // A live desktop flushes its profile on quit; write only after it exits.
            profileAttempted = true
            desktopProfileRestorationRequired = true
            try profileManager.activate(
                providers: candidate.providers, configuration: candidate.codex, signature: signature
            )
            desktopRoutingSelection = DesktopRoutingSelection(configuration: candidate)
            await replaceGatewayRouting(with: candidate)
            try checkChatGPTOperation()
            try await openManagedChatGPT(using: controller)
            try checkChatGPTOperation()
            try validateDesktopSettings(unchangedSince: previous)
            candidate = retainingCurrentImageObservations(in: candidate)
            try configurationStore.save(candidate)
            configuration = candidate
            desktopRoutingSelection = nil
            await replaceGatewayRoutingIfNeeded()
            appliedCodexState = .connected(
                AppliedCodexSnapshot(
                    configuration: candidate.codex, providers: candidate.providers, signature: signature)
            )
            pendingCodexSettings = nil
            desktopProfileRestorationRequired = false
            pendingChatGPTSettings = nil
            reconcileOpenCodeDraft()
            chatGPTStatus = .connected
        } catch {
            desktopRoutingSelection = nil
            let restored = await rollbackDesktopClients(
                checkpoint: DesktopCheckpoint(
                    configuration: previous, applied: previousApplied, desktop: previousDesktop),
                quit: quit,
                profileAttempted: profileAttempted
            )
            guard restored else { throw ChatGPTConnectionError.rollbackFailed }
            if error as? ChatGPTLaunchEnvironment.Error == .conflictingBackend {
                throw ChatGPTConnectionError.conflictingEnvironment
            }
            throw error
        }
    }

    private func disconnectDesktopClientsTransaction() async throws {
        let previous = configuration
        let previousApplied = appliedCodexState
        let previousDesktop = chatGPTDesktopRestoration
        var quit = DesktopQuitState.untouched
        var profileAttempted = false
        do {
            guard let controller = codexController, let profileManager = codexProfileManager else {
                throw ChatGPTConnectionError.unavailable
            }
            quit = .requested
            try await controller.quitAndWait()
            quit = .completed
            chatGPTDesktopRestoration = .relaunchRequired
            try checkChatGPTOperation()
            try validateDesktopSettings(unchangedSince: previous)
            if configuration.codex.connected || desktopProfileRestorationRequired {
                profileAttempted = true
                desktopProfileRestorationRequired = true
                try profileManager.restore()
            }
            var candidate = configuration
            candidate.codex.connected = false
            candidate.chatgpt.connected = false
            desktopRoutingSelection = DesktopRoutingSelection(configuration: candidate)
            await replaceGatewayRouting(with: candidate)
            try checkChatGPTOperation()
            try await controller.open(environment: normalDesktopEnvironment)
            chatGPTManagedLaunchID = nil
            chatGPTDesktopRestoration = .normal
            try checkChatGPTOperation()
            try validateDesktopSettings(unchangedSince: previous)
            candidate = retainingCurrentImageObservations(in: candidate)
            try configurationStore.save(candidate)
            configuration = candidate
            desktopRoutingSelection = nil
            await replaceGatewayRoutingIfNeeded()
            appliedCodexState = .disconnected
            desktopProfileRestorationRequired = false
            pendingCodexSettings = nil
            pendingChatGPTSettings = nil
            await stopChatGPTListener()
            chatGPTStatus = .disconnected
        } catch {
            desktopRoutingSelection = nil
            let restored = await rollbackDesktopClients(
                checkpoint: DesktopCheckpoint(
                    configuration: previous, applied: previousApplied, desktop: previousDesktop),
                quit: quit,
                profileAttempted: profileAttempted
            )
            guard restored else { throw ChatGPTConnectionError.rollbackFailed }
            throw error
        }
    }

    private func rollbackDesktopClients(
        checkpoint: DesktopCheckpoint,
        quit: DesktopQuitState,
        profileAttempted: Bool
    ) async -> Bool {
        let cancelled = Task.isCancelled
        let restoration = Task {
            await self.restoreDesktopClients(
                checkpoint: checkpoint,
                quit: quit,
                cancelled: cancelled,
                profileAttempted: profileAttempted
            )
        }
        return await restoration.value
    }

    private func restoreDesktopClients(
        checkpoint: DesktopCheckpoint,
        quit: DesktopQuitState,
        cancelled: Bool,
        profileAttempted: Bool
    ) async -> Bool {
        let reopen: Bool
        do {
            reopen = try await completeDesktopRollbackQuit(quit, cancelled: cancelled)
        } catch {
            chatGPTStatus = .needsAttention
            return false
        }
        var restored = true
        if profileAttempted, let profileManager = codexProfileManager {
            restored = await rollbackCodexApply(
                to: configuration, appliedState: checkpoint.applied, profileManager: profileManager)
            desktopProfileRestorationRequired = !restored
        } else {
            await replaceGatewayRoutingIfNeeded()
        }
        let desktopRestored = await restoreChatGPTLaunch(to: checkpoint.desktop, reopen: reopen)
        restored = restored && desktopRestored
        chatGPTStatus = checkpoint.configuration.chatgpt.connected || !restored ? .needsAttention : .disconnected
        return restored
    }
}
