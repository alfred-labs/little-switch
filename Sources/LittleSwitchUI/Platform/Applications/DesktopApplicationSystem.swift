import AppKit
import Foundation
import LittleSwitchCommon

/// Read-only platform discovery. No profile files, credentials, or organization
/// identifiers escape this boundary; consumers receive only availability.
@MainActor
enum DesktopApplicationSystem {
    static func manager(workspace: NSWorkspace = .shared) -> DesktopApplicationManager {
        let locator = locator(workspace: workspace)
        return DesktopApplicationManager(
            locateApplication: { locator.applicationURL(for: $0) },
            isClaudeOrganizationManaged: { claudeOrganizationIsManaged() },
            openApplication: { try await open($0, workspace: workspace) }
        )
    }

    static func locator(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) -> DesktopApplicationLocator {
        DesktopApplicationLocator(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            runningApplication: { identifier in
                workspace.runningApplications.first {
                    $0.bundleIdentifier == identifier && !$0.isTerminated
                }?.bundleURL
            },
            registeredApplication: { workspace.urlForApplication(withBundleIdentifier: $0) },
            bundleIdentifier: { url in
                guard fileManager.fileExists(atPath: url.path) else { return nil }
                return Bundle(url: url)?.bundleIdentifier
            }
        )
    }

    static func claudeOrganizationIsManaged() -> Bool {
        let domain = DesktopApplication.claude.bundleIdentifier as CFString
        let key = "forceLoginOrgUUID" as CFString
        return ClaudeManagedPreferences.restrictsOrganization(
            value: CFPreferencesCopyAppValue(key, domain),
            isForced: CFPreferencesAppValueIsForced(key, domain)
        )
    }

    static func open(_ url: URL, workspace: NSWorkspace, environment: [String: String] = [:]) async throws {
        _ = try await openTracked(url, workspace: workspace, environment: environment)
    }

    static func openTracked(
        _ url: URL, workspace: NSWorkspace, environment: [String: String]
    ) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.environment = environment
        return try await withCheckedThrowingContinuation { continuation in
            workspace.openApplication(at: url, configuration: configuration) { application, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let application {
                    continuation.resume(returning: application)
                } else {
                    continuation.resume(throwing: NSWorkspaceCodexController.Error.applicationNotFound)
                }
            }
        }
    }
}
