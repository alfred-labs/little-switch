import LittleSwitchCommon

extension ApplicationCoordinator {
    func requireUnmanagedClaudeDesktop() async throws {
        guard await desktopApplications?.availability().claude != .organizationManaged else {
            throw DesktopApplicationLaunchError.organizationManaged
        }
    }

    public func openDesktopApplication(_ application: DesktopApplication) async throws {
        if application == .codex, configuration.chatgpt.connected {
            _ = try await openChatGPT()
            return
        }
        guard let desktopApplications else {
            throw DesktopApplicationLaunchError.notInstalled(application)
        }
        try await desktopApplications.open(application)
    }
}
