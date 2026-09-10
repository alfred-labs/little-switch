enum LaunchAtLoginStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
final class LaunchAtLoginController {
    private let service: any LaunchAtLoginServicing

    init(service: any LaunchAtLoginServicing) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        service.status
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        let current = service.status
        switch (enabled, current) {
        case (true, .enabled),
            (true, .requiresApproval),
            (false, .disabled),
            (false, .unavailable):
            return current
        case (true, .disabled),
            (true, .unavailable):
            // `.unavailable` maps SMAppService `.notFound`, which macOS also
            // reports for apps that were never registered; `register()`
            // still succeeds from there, so attempt it and surface any
            // failure instead of silently no-opping.
            try service.register()
        case (false, .enabled), (false, .requiresApproval):
            try service.unregister()
        }
        return service.status
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
