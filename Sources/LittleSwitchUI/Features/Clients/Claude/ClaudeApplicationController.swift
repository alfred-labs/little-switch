import AppKit
import Foundation

public protocol ClaudeApplicationControlling: ApplicationRelaunching {}

@MainActor
public final class NSWorkspaceClaudeController: ClaudeApplicationControlling {
    public enum Error: Swift.Error, Equatable {
        case applicationNotFound
        case quitTimedOut
    }

    private static let bundleIdentifier = "com.anthropic.claudefordesktop"
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
            guard isRunning() else {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Error.quitTimedOut
    }

    public func open() async throws {
        guard let applicationURL else {
            throw Error.applicationNotFound
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            workspace.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private var runningApplications: [NSRunningApplication] {
        workspace.runningApplications.filter {
            $0.bundleIdentifier == Self.bundleIdentifier && !$0.isTerminated
        }
    }

    private var applicationURL: URL? {
        [
            URL(filePath: "/Applications/Claude.app"),
            fileManager.homeDirectoryForCurrentUser
                .appending(path: "Applications", directoryHint: .isDirectory)
                .appending(path: "Claude.app", directoryHint: .isDirectory),
        ].first { fileManager.fileExists(atPath: $0.path) }
    }
}
