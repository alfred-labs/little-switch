import ServiceManagement

@MainActor
final class ServiceManagementLaunchAtLoginService: LaunchAtLoginServicing {
    private let service: SMAppService

    init(service: SMAppService = SMAppService.mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        Self.normalizedStatus(for: service.status)
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func normalizedStatus(
        for status: SMAppService.Status
    ) -> LaunchAtLoginStatus {
        switch status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }
}
