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

    func beginChatGPTOperation() throws {
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
        let previous = configuration
        let wasConnected = configuration.chatgpt.connected
        let previousDesktop = chatGPTDesktopRestoration
        var quit = DesktopQuitState.untouched
        do {
            guard let controller = codexController else { throw ChatGPTConnectionError.unavailable }
            var candidate = applyingChatGPTDraft(to: configuration)
            guard candidate.chatgpt.resolvedModel(in: candidate.providers) != nil else {
                throw ChatGPTConnectionError.noModels
            }
            _ = try ChatGPTLaunchEnvironment.connected(inheriting: inheritedEnvironment)
            try await startGateway(snapshot: routingSnapshot())
            try checkChatGPTOperation()
            try await startChatGPTListener(installTrust: true)
            try checkChatGPTOperation()
            try validateDesktopSettings(unchangedSince: previous)
            // Starting the listener must succeed before interrupting the app.
            quit = .requested
            try await controller.quitAndWait()
            quit = .completed
            chatGPTDesktopRestoration = .relaunchRequired
            try validateDesktopSettings(unchangedSince: previous)
            candidate.chatgpt.connected = true
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
            pendingChatGPTSettings = nil
            chatGPTStatus = .connected
        } catch {
            desktopRoutingSelection = nil
            await replaceGatewayRoutingIfNeeded()
            let restored = await rollbackChatGPTLaunch(to: previousDesktop, quit: quit)
            chatGPTStatus = wasConnected || !restored ? .needsAttention : .disconnected
            guard restored else { throw ChatGPTConnectionError.rollbackFailed }
            if error as? ChatGPTLaunchEnvironment.Error == .conflictingBackend {
                throw ChatGPTConnectionError.conflictingEnvironment
            }
            throw error
        }
    }

    var normalDesktopEnvironment: [String: String] {
        inheritedEnvironment.filter { key, value in
            !(["CODEX_API_BASE_URL", "CODEX_APP_SERVER_CHATGPT_BASE_URL"].contains(key)
                && value.trimmingCharacters(in: .whitespacesAndNewlines) == ChatGPTLaunchEnvironment.apiBaseURL)
        }
    }
}
