extension LittleSwitchApplicationDelegate {
    func refreshLaunchAtLogin() {
        model.launchAtLoginStatus = launchAtLoginController.status
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) async {
        model.isChangingLaunchAtLogin = true
        defer { model.isChangingLaunchAtLogin = false }

        do {
            model.launchAtLoginStatus = try launchAtLoginController.setEnabled(enabled)
        } catch {
            model.launchAtLoginStatus = launchAtLoginController.status
            present(error)
        }
    }

    func openLoginItemsSettings() {
        launchAtLoginController.openSystemSettings()
    }
}
