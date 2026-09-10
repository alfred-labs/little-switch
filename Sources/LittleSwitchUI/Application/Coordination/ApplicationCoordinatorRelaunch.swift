import Foundation
import LittleSwitchCore
import OSLog

extension ApplicationCoordinator {
    /// Puts the switches back where the user left them before the last quit.
    ///
    /// Quitting restores every managed profile so the gateway's address never
    /// outlives the running app, which also clears `connected`. The recorded
    /// intent is therefore the only trace of what was on.
    ///
    /// A product that fails to reconnect stays recorded so the next launch
    /// tries again, and the failure is logged rather than swallowed: a switch
    /// that silently refuses to come back is indistinguishable from one that
    /// was never remembered.
    func reconnectRelaunchTargets() async {
        var targets = configuration.relaunchTargets
        guard !targets.isEmpty else {
            return
        }
        if targets.claude {
            targets.claude = !(await reconnect("Claude Desktop") { try await connect() })
        }
        if targets.codex {
            targets.codex = !(await reconnect("Codex") { try await connectCodex() })
        }
        if targets.claudeCode {
            targets.claudeCode =
                !(await reconnect("Claude Code") { try await connectClaudeCode() })
        }
        if targets.openCode {
            targets.openCode = !(await reconnect("OpenCode") { try await connectOpenCode() })
        }
        configuration.relaunchTargets = targets
        try? configurationStore.save(configuration)
    }

    private func reconnect(
        _ product: String,
        using connect: () async throws -> CoordinatorSnapshot
    ) async -> Bool {
        do {
            _ = try await connect()
            return true
        } catch {
            Self.relaunchLogger.error(
                "Could not restore \(product, privacy: .public) on launch: \(error)"
            )
            return false
        }
    }

    private static let relaunchLogger = Logger(
        subsystem: ProductIdentity.logSubsystem,
        category: "relaunch"
    )
}
