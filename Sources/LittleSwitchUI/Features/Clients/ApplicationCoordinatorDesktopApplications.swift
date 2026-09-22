import LittleSwitchCommon

extension ApplicationCoordinator {
    func requireUnmanagedClaudeDesktop() async throws {
        guard await desktopApplications?.availability().claude != .organizationManaged else {
            throw DesktopApplicationLaunchError.organizationManaged
        }
    }

    public func openDesktopApplication(_ application: DesktopApplication) async throws {
        guard let desktopApplications else {
            throw DesktopApplicationLaunchError.notInstalled(application)
        }
        try await desktopApplications.open(application)
    }
}
