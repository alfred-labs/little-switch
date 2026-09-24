import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    func startChatGPTListener(installTrust: Bool) async throws {
        guard let tlsProvisioner, let builder = chatGPTGatewayBuilder, let gatewayState else {
            throw ChatGPTConnectionError.unavailable
        }
        // Startup checks trust before identity: recovery cannot provision or
        // request consent merely because saved connection intent exists.
        if !installTrust, !tlsProvisioner.isTrusted(secretStore: secretStore) {
            throw ChatGPTConnectionError.trustRequired
        }
        guard let identity = tlsProvisioner.identity(secretStore: secretStore) else {
            throw ChatGPTConnectionError.trustRequired
        }
        let trusted =
            installTrust
            ? tlsProvisioner.installTrust(secretStore: secretStore).isTrusted
            : tlsProvisioner.isTrusted(secretStore: secretStore)
        guard trusted else { throw ChatGPTConnectionError.trustRequired }
        if let chatGPTServer, chatGPTGatewayState === gatewayState, await chatGPTServer.isRunning { return }
        // A listener owns active turns and its history actor. Drain it before
        // constructing another owner, including after a primary state change.
        await stopChatGPTListener()
        try checkChatGPTOperation()
        guard self.gatewayState === gatewayState else { throw ChatGPTConnectionError.unavailable }
        let server = try builder.makeGateway(
            state: gatewayState,
            secretStore: secretStore,
            identity: identity,
            monitoring: gatewayMonitoring
        )
        chatGPTServer = server
        chatGPTGatewayState = gatewayState
        do { try await server.start() } catch {
            await server.stop()
            chatGPTServer = nil
            chatGPTGatewayState = nil
            throw error
        }
        try checkChatGPTOperation()
    }

    func recoverChatGPTAtStartup() async {
        guard configuration.chatgpt.connected, !isShuttingDown else { return }
        // Register recovery in the same operation slot so shutdown waits for a
        // suspended bind and never lets a late listener escape ownership.
        let operation = Task { try await self.startChatGPTListener(installTrust: false) }
        chatGPTOperation = operation
        defer { chatGPTOperation = nil }
        do {
            try await operation.value
            chatGPTStatus = .ready
        } catch {
            chatGPTStatus = .needsAttention
        }
    }

    func stopChatGPTListener() async {
        let server = chatGPTServer
        chatGPTServer = nil
        chatGPTGatewayState = nil
        await server?.stop()
    }

    /// A refused desktop quit cancels LittleSwitch termination. The listener
    /// and saved ownership remain until the user can complete restoration.
    func prepareChatGPTShutdown(mode: ApplicationShutdownMode) async -> Bool {
        chatGPTOperation?.cancel()
        _ = try? await chatGPTOperation?.value
        if mode == .userQuit, configuration.chatgpt.connected || chatGPTDesktopRestoration.requiresRestoration {
            guard let controller = codexController else {
                chatGPTStatus = .needsAttention
                return false
            }
            do {
                let running = await controller.isRunning()
                if running {
                    try await controller.quitAndWait()
                    chatGPTDesktopRestoration = .relaunchRequired
                }
                try restoreSharedCodexProfileForShutdown()
                if running || chatGPTDesktopRestoration.requiresRestoration {
                    try await controller.open(environment: normalDesktopEnvironment)
                }
                chatGPTDesktopRestoration = .normal
                chatGPTManagedLaunchID = nil
            } catch {
                chatGPTStatus = .needsAttention
                return false
            }
        }
        await stopChatGPTListener()
        chatGPTStatus = configuration.chatgpt.connected ? .ready : .disconnected
        return true
    }

    private func restoreSharedCodexProfileForShutdown() throws {
        guard configuration.codex.connected else { return }
        guard let codexProfileManager, case .connected(let applied) = appliedCodexState else {
            throw ChatGPTConnectionError.rollbackFailed
        }
        do {
            try codexProfileManager.restore()
            var candidate = configuration
            candidate.codex.connected = false
            // If the subsequent desktop open fails, a retry must still retain
            // Codex's reconnect intent even though its profile is restored.
            candidate.relaunchTargets.codex = true
            try configurationStore.save(candidate)
            configuration = candidate
            appliedCodexState = .disconnected
        } catch {
            try codexProfileManager.activate(
                providers: applied.providers,
                configuration: applied.configuration,
                signature: applied.signature
            )
            throw error
        }
    }
}
