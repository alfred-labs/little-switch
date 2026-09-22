import LittleSwitchCommon

extension LittleSwitchApplicationDelegate {
    func openDesktopApplication(_ application: DesktopApplication) {
        guard let coordinator, !model.isBusy,
            model.desktopApplications[application] == .available,
            model.launchingApplications.insert(application).inserted
        else { return }
        Task {
            defer { model.launchingApplications.remove(application) }
            do {
                try await coordinator.openDesktopApplication(application)
            } catch is CancellationError {
            } catch {
                // Launching is independent from profile transactions: a late
                // launch failure must not clear another operation's busy flag.
                model.errorMessage = startupErrorMessage(for: error)
                showMainWindow()
            }
        }
    }
}
