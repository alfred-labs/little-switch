import AppKit
import Foundation

public protocol CodexApplicationControlling: ApplicationRelaunching {}

@MainActor
public final class NSWorkspaceCodexController: CodexApplicationControlling {
    public enum Error: Swift.Error, Equatable {
        case applicationNotFound
        case quitTimedOut
    }

    nonisolated package static let bundleIdentifier = "com.openai.codex"

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

    nonisolated package static func applicationCandidates(homeDirectory: URL) -> [URL] {
        [
            URL(filePath: "/Applications/Codex.app"),
            URL(filePath: "/Applications/ChatGPT.app"),
            homeDirectory
                .appending(path: "Applications", directoryHint: .isDirectory)
                .appending(path: "Codex.app", directoryHint: .isDirectory),
            homeDirectory
                .appending(path: "Applications", directoryHint: .isDirectory)
                .appending(path: "ChatGPT.app", directoryHint: .isDirectory),
        ]
    }

    private var runningApplications: [NSRunningApplication] {
        workspace.runningApplications.filter {
            $0.bundleIdentifier == Self.bundleIdentifier && !$0.isTerminated
        }
    }

    private var applicationURL: URL? {
        Self.applicationCandidates(homeDirectory: fileManager.homeDirectoryForCurrentUser)
            .first { fileManager.fileExists(atPath: $0.path) }
    }
}
