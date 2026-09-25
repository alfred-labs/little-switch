import LittleSwitchCore

/// A cancelled termination wait may already have sent the app its quit request.
enum DesktopQuitState: Sendable {
    case untouched
    case requested
    case completed
}

extension ApplicationCoordinator {
    func rollbackChatGPTLaunch(to previous: ChatGPTDesktopRestorationState, quit: DesktopQuitState) async -> Bool {
        let cancelled = Task.isCancelled
        // Cleanup must finish even when the initiating request was cancelled.
        let restoration = Task {
            do {
                let reopen = try await self.completeDesktopRollbackQuit(quit, cancelled: cancelled)
                return await self.restoreChatGPTLaunch(to: previous, reopen: reopen)
            } catch { return false }
        }
        return await restoration.value
    }

    /// Stop the candidate before any profile restoration: Desktop flushes its
    /// in-memory profile on quit. Shutdown may suppress reopening, but not this step.
    func completeDesktopRollbackQuit(_ quit: DesktopQuitState, cancelled: Bool) async throws -> Bool {
        guard quit == .completed || (quit == .requested && cancelled) else { return false }
        guard let controller = codexController else { throw ChatGPTConnectionError.unavailable }
        if await controller.isRunning() { try await controller.quitAndWait() }
        chatGPTDesktopRestoration = .relaunchRequired
        return true
    }

    func restoreChatGPTLaunch(to previous: ChatGPTDesktopRestorationState, reopen: Bool) async -> Bool {
        // Shutdown owns the normal relaunch once the transaction settles.
        guard !isShuttingDown else { return true }
        if reopen, let controller = codexController {
            do {
                let restoreManaged = await canRestoreManagedChatGPT(previous)
                guard !isShuttingDown else { return true }
                if restoreManaged {
                    try await openManagedChatGPT(using: controller)
                } else {
                    try await controller.open(environment: normalDesktopEnvironment)
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
}
