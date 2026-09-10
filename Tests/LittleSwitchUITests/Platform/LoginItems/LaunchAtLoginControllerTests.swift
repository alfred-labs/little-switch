import ServiceManagement
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Launch at login controller")
struct LaunchAtLoginControllerTests {
    @Test("ServiceManagement statuses map to presentation-safe states")
    func statusMapping() {
        #expect(
            ServiceManagementLaunchAtLoginService.normalizedStatus(for: .notRegistered)
                == .disabled
        )
        #expect(
            ServiceManagementLaunchAtLoginService.normalizedStatus(for: .enabled)
                == .enabled
        )
        #expect(
            ServiceManagementLaunchAtLoginService.normalizedStatus(for: .requiresApproval)
                == .requiresApproval
        )
        #expect(
            ServiceManagementLaunchAtLoginService.normalizedStatus(for: .notFound)
                == .unavailable
        )
    }

    @Test("Enabling and disabling use the system service once and return its state")
    func transitions() throws {
        let service = RecordingLaunchAtLoginService(status: .disabled)
        let controller = LaunchAtLoginController(service: service)

        service.statusAfterRegister = .enabled
        #expect(try controller.setEnabled(true) == .enabled)
        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 0)

        service.statusAfterUnregister = .disabled
        #expect(try controller.setEnabled(false) == .disabled)
        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 1)
    }

    @Test("Requested, active, and disabled states are idempotent")
    func idempotence() throws {
        for (requested, status) in [
            (true, LaunchAtLoginStatus.enabled),
            (true, .requiresApproval),
            (false, .disabled),
            (false, .unavailable),
        ] {
            let service = RecordingLaunchAtLoginService(status: status)
            let controller = LaunchAtLoginController(service: service)

            #expect(try controller.setEnabled(requested) == status)
            #expect(service.registerCount == 0)
            #expect(service.unregisterCount == 0)
        }
    }

    @Test("Enabling from unavailable attempts registration")
    func enableFromUnavailable() throws {
        // `.unavailable` maps SMAppService `.notFound`, which macOS reports
        // for apps that were never registered — `register()` still succeeds
        // from there, so the controller must attempt it rather than no-op.
        let service = RecordingLaunchAtLoginService(status: .unavailable)
        service.statusAfterRegister = .enabled
        let controller = LaunchAtLoginController(service: service)

        #expect(try controller.setEnabled(true) == .enabled)
        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 0)
    }

    @Test("A pending approval can be explicitly unregistered")
    func cancelPendingApproval() throws {
        let service = RecordingLaunchAtLoginService(status: .requiresApproval)
        service.statusAfterUnregister = .disabled
        let controller = LaunchAtLoginController(service: service)

        #expect(try controller.setEnabled(false) == .disabled)
        #expect(service.unregisterCount == 1)
    }

    @Test("Registration and unregistration errors preserve the reported state")
    func errors() {
        let registration = RecordingLaunchAtLoginService(status: .disabled)
        registration.registerError = LaunchAtLoginTestError.injected
        let registrationController = LaunchAtLoginController(service: registration)

        #expect(throws: LaunchAtLoginTestError.injected) {
            try registrationController.setEnabled(true)
        }
        #expect(registrationController.status == .disabled)

        let unregistration = RecordingLaunchAtLoginService(status: .enabled)
        unregistration.unregisterError = LaunchAtLoginTestError.injected
        let unregistrationController = LaunchAtLoginController(service: unregistration)

        #expect(throws: LaunchAtLoginTestError.injected) {
            try unregistrationController.setEnabled(false)
        }
        #expect(unregistrationController.status == .enabled)
    }

    @Test("Opening Login Items is delegated to the system service")
    func openLoginItems() {
        let service = RecordingLaunchAtLoginService(status: .requiresApproval)
        let controller = LaunchAtLoginController(service: service)

        controller.openSystemSettings()

        #expect(service.openSystemSettingsCount == 1)
    }
}

private enum LaunchAtLoginTestError: Swift.Error, Equatable {
    case injected
}

@MainActor
private final class RecordingLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus
    var statusAfterRegister: LaunchAtLoginStatus?
    var statusAfterUnregister: LaunchAtLoginStatus?
    var registerError: LaunchAtLoginTestError?
    var unregisterError: LaunchAtLoginTestError?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSystemSettingsCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let registerError {
            throw registerError
        }
        if let statusAfterRegister {
            status = statusAfterRegister
        }
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError {
            throw unregisterError
        }
        if let statusAfterUnregister {
            status = statusAfterUnregister
        }
    }

    func openSystemSettings() {
        openSystemSettingsCount += 1
    }
}
