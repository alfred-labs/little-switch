import Foundation
import LittleSwitchCommon

public protocol DesktopApplicationManaging: Sendable {
    @MainActor func availability() -> DesktopApplicationAvailability
    @MainActor func open(_ application: DesktopApplication) async throws
}

@MainActor
final class DesktopApplicationManager: DesktopApplicationManaging {
    private let locateApplication: (DesktopApplication) -> URL?
    private let isClaudeOrganizationManaged: () -> Bool
    private let openApplication: (URL) async throws -> Void

    init(
        locateApplication: @escaping (DesktopApplication) -> URL?,
        isClaudeOrganizationManaged: @escaping () -> Bool,
        openApplication: @escaping (URL) async throws -> Void
    ) {
        self.locateApplication = locateApplication
        self.isClaudeOrganizationManaged = isClaudeOrganizationManaged
        self.openApplication = openApplication
    }

    func availability() -> DesktopApplicationAvailability {
        DesktopApplicationAvailability(
            claude: access(for: .claude),
            codex: access(for: .codex),
            openCode: access(for: .openCode)
        )
    }

    func open(_ application: DesktopApplication) async throws {
        guard let url = locateApplication(application) else {
            throw DesktopApplicationLaunchError.notInstalled(application)
        }
        guard application != .claude || !isClaudeOrganizationManaged() else {
            throw DesktopApplicationLaunchError.organizationManaged
        }
        do {
            try await openApplication(url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DesktopApplicationLaunchError.launchFailed(application)
        }
    }

    private func access(for application: DesktopApplication) -> DesktopApplicationAccess {
        guard locateApplication(application) != nil else { return .notInstalled }
        return application == .claude && isClaudeOrganizationManaged() ? .organizationManaged : .available
    }
}
