import Foundation
import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    public func connectChatGPT() async throws -> CoordinatorSnapshot {
        try beginChatGPTOperation()
        chatGPTStatus = .connecting
        let operation = Task { try await self.connectChatGPTTransaction() }
        chatGPTOperation = operation
        defer { chatGPTOperation = nil }
        try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
        return await snapshot()
    }

    /// Reloading always reopens the shared desktop process, including when it
    /// was launched normally outside LittleSwitch since the last connection.
    public func openChatGPT() async throws -> CoordinatorSnapshot {
        try await connectChatGPT()
    }

    public func disconnectChatGPT() async throws -> CoordinatorSnapshot {
        try beginChatGPTOperation()
        guard configuration.chatgpt.connected || chatGPTDesktopRestoration.requiresRestoration else {
            return await snapshot()
        }
        chatGPTStatus = .disconnecting
        let operation = Task { try await self.disconnectChatGPTTransaction() }
        chatGPTOperation = operation
        defer { chatGPTOperation = nil }
        try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
        return await snapshot()
    }

    private func beginChatGPTOperation() throws {
        guard !isShuttingDown else { throw CancellationError() }
        guard chatGPTOperation == nil, !codexDesktopOperationInProgress else {
            throw ChatGPTConnectionError.operationInProgress
        }
    }

    func checkChatGPTOperation() throws {
        try Task.checkCancellation()
        guard !isShuttingDown else { throw CancellationError() }
    }

    private func connectChatGPTTransaction() async throws {
        let wasConnected = configuration.chatgpt.connected
        let previousDesktop = chatGPTDesktopRestoration
        var quit = false
        do {
            guard let controller = codexController else { throw ChatGPTConnectionError.unavailable }
            guard !configuration.codex.exposedModels(in: configuration.providers).isEmpty else {
                throw ChatGPTConnectionError.noModels
            }
            guard !hasPendingCodexChanges else { throw ChatGPTConnectionError.pendingCodex }
            let environment = try ChatGPTLaunchEnvironment.connected(inheriting: inheritedEnvironment)
            try await startGateway(snapshot: routingSnapshot())
            try checkChatGPTOperation()
            try await startChatGPTListener(installTrust: true)
            try checkChatGPTOperation()
            // Starting the listener must succeed before interrupting the app.
            try await controller.quitAndWait()
            quit = true
            chatGPTDesktopRestoration = .relaunchRequired
            try checkChatGPTOperation()
            try await openManagedChatGPT(using: controller, environment: environment)
            try checkChatGPTOperation()
            var candidate = configuration
            candidate.chatgpt.connected = true
            try configurationStore.save(candidate)
            configuration = candidate
            chatGPTStatus = .connected
        } catch {
            let restored = await rollbackChatGPTLaunch(to: previousDesktop, quit: quit)
            chatGPTStatus = wasConnected || !restored ? .needsAttention : .disconnected
            guard restored else { throw ChatGPTConnectionError.rollbackFailed }
            if error as? ChatGPTLaunchEnvironment.Error == .conflictingBackend {
                throw ChatGPTConnectionError.conflictingEnvironment
            }
            throw error
        }
    }

    private func disconnectChatGPTTransaction() async throws {
        let previousDesktop = chatGPTDesktopRestoration
        var quit = false
        do {
            guard let controller = codexController else { throw ChatGPTConnectionError.unavailable }
            try await controller.quitAndWait()
            quit = true
            chatGPTDesktopRestoration = .relaunchRequired
            try checkChatGPTOperation()
            try await controller.open(environment: normalDesktopEnvironment)
            chatGPTManagedLaunchID = nil
            chatGPTDesktopRestoration = .normal
            try checkChatGPTOperation()
            var candidate = configuration
            candidate.chatgpt.connected = false
            try configurationStore.save(candidate)
            configuration = candidate
            await stopChatGPTListener()
            chatGPTStatus = .disconnected
        } catch {
            let restored = await rollbackChatGPTLaunch(to: previousDesktop, quit: quit)
            chatGPTStatus = .needsAttention
            guard restored else { throw ChatGPTConnectionError.rollbackFailed }
            throw error
        }
    }

    private func rollbackChatGPTLaunch(to previous: ChatGPTDesktopRestorationState, quit: Bool) async -> Bool {
        // Shutdown owns the normal relaunch once this transaction settles.
        guard !isShuttingDown else { return true }
        if quit, let controller = codexController {
            do {
                let running = await controller.isRunning()
                guard !isShuttingDown else { return true }
                if running { try await controller.quitAndWait() }
                chatGPTDesktopRestoration = .relaunchRequired
                guard !isShuttingDown else { return true }
                // Saved intent cannot establish the desktop's previous launch
                // environment. Even a known managed launch can only be restored
                // while its listener remains available and trusted.
                let restoreManaged = await canRestoreManagedChatGPT(previous)
                guard !isShuttingDown else { return true }
                let environment =
                    restoreManaged
                    ? try ChatGPTLaunchEnvironment.connected(inheriting: inheritedEnvironment)
                    : normalDesktopEnvironment
                if restoreManaged {
                    try await openManagedChatGPT(using: controller, environment: environment)
                } else {
                    try await controller.open(environment: environment)
                    chatGPTManagedLaunchID = nil
                    chatGPTDesktopRestoration = .normal
                }
            } catch { return false }
        }
        if !configuration.chatgpt.connected { await stopChatGPTListener() }
        return true
    }

    private func canRestoreManagedChatGPT(_ previous: ChatGPTDesktopRestorationState) async -> Bool {
        guard previous == .managed,
            tlsProvisioner?.isTrusted(secretStore: secretStore) == true,
            let chatGPTServer
        else { return false }
        return await chatGPTServer.isRunning
    }

    var normalDesktopEnvironment: [String: String] {
        inheritedEnvironment.filter { key, value in
            !(["CODEX_API_BASE_URL", "CODEX_APP_SERVER_CHATGPT_BASE_URL"].contains(key)
                && value.trimmingCharacters(in: .whitespacesAndNewlines) == ChatGPTLaunchEnvironment.apiBaseURL)
        }
    }
}
