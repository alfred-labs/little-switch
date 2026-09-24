import Foundation

extension ApplicationCoordinator {
    /// Saved intent and restoration responsibility survive process exit. Only
    /// the exact process launched with our environment can remain Connected.
    func reconcileChatGPTConnection() async {
        guard chatGPTStatus == .connected || chatGPTStatus == .ready,
            !isShuttingDown, chatGPTOperation == nil, !codexDesktopOperationInProgress
        else { return }
        let launchID = chatGPTManagedLaunchID
        let state = chatGPTGatewayState
        let listenerRunning = await chatGPTServer?.isRunning ?? false
        let managedRunning: Bool
        if let launchID, let codexController {
            managedRunning = await codexController.isRunning(launchID: launchID)
        } else {
            managedRunning = false
        }
        // Platform queries suspend this actor; a newer transaction owns status.
        guard chatGPTOperation == nil, !codexDesktopOperationInProgress, !isShuttingDown,
            chatGPTManagedLaunchID == launchID, chatGPTGatewayState === state,
            chatGPTStatus == .connected || chatGPTStatus == .ready
        else { return }
        guard listenerRunning, state != nil, state === gatewayState else {
            chatGPTStatus = .needsAttention
            return
        }
        chatGPTStatus = managedRunning ? .connected : .ready
    }

    func openManagedChatGPT(
        using controller: any CodexApplicationControlling,
        environment: [String: String]
    ) async throws {
        chatGPTManagedLaunchID = try await controller.openTracked(environment: environment)
        chatGPTDesktopRestoration = .managed
    }
}
