import AppKit
import Foundation
import LittleSwitchCommon

public protocol CodexApplicationControlling: ApplicationRelaunching {}

@MainActor
public final class NSWorkspaceCodexController: CodexApplicationControlling {
    public enum Error: Swift.Error, Equatable {
        case applicationNotFound
        case quitTimedOut
    }

    nonisolated package static let bundleIdentifier = DesktopApplication.codex.bundleIdentifier

    private let workspace: NSWorkspace
    private let fileManager: FileManager

    public init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    public func isRunning() -> Bool {
        !runningApplications.isEmpty
    }

    public func quitAndWait() async throws {
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

    public func open() async throws {
        guard let applicationURL else {
            throw Error.applicationNotFound
        }
        try await DesktopApplicationSystem.open(applicationURL, workspace: workspace)
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
