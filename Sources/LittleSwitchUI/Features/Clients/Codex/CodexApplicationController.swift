import AppKit
import Foundation
import LittleSwitchCommon

public protocol CodexApplicationControlling: ApplicationRelaunching {
    func open(environment: [String: String]) async throws
    func openTracked(environment: [String: String]) async throws -> UUID
    func isRunning(launchID: UUID) async -> Bool
}

extension CodexApplicationControlling {
    public func openTracked(environment: [String: String]) async throws -> UUID {
        throw ChatGPTConnectionError.unavailable
    }

    public func isRunning(launchID: UUID) async -> Bool { false }

    public func open(environment: [String: String]) async throws {
        guard environment.isEmpty else { throw ChatGPTConnectionError.unavailable }
        try await open()
    }
}

@MainActor
final class NSWorkspaceCodexController: CodexApplicationControlling {
    enum Error: Swift.Error, Equatable {
        case applicationNotFound
        case quitTimedOut
    }

    nonisolated package static let bundleIdentifier = DesktopApplication.codex.bundleIdentifier

    private let workspace: NSWorkspace
    private let fileManager: FileManager
    private var trackedLaunch: (id: UUID, application: NSRunningApplication)?

    init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func isRunning() -> Bool {
        !runningApplications.isEmpty
    }

    func quitAndWait() async throws {
        for application in runningApplications {
            application.terminate()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            guard !isRunning() else {
                try await Task.sleep(for: .milliseconds(100))
                continue
            }
            return
        }
        throw Error.quitTimedOut
    }

    func open() async throws {
        try await open(environment: [:])
    }

    func open(environment: [String: String]) async throws {
        _ = try await openTracked(environment: environment)
    }

    func isRunning(launchID: UUID) -> Bool {
        guard let trackedLaunch, trackedLaunch.id == launchID else { return false }
        return !trackedLaunch.application.isTerminated
    }

    func openTracked(environment: [String: String]) async throws -> UUID {
        guard let applicationURL else {
            throw Error.applicationNotFound
        }
        let application = try await DesktopApplicationSystem.openTracked(
            applicationURL, workspace: workspace, environment: environment)
        let id = UUID()
        trackedLaunch = (id, application)
        return id
    }

    private var runningApplications: [NSRunningApplication] {
        workspace.runningApplications.filter {
            $0.bundleIdentifier == Self.bundleIdentifier && !$0.isTerminated
        }
    }

    private var applicationURL: URL? {
        DesktopApplicationSystem.locator(workspace: workspace, fileManager: fileManager)
            .applicationURL(for: .codex)
    }
}
