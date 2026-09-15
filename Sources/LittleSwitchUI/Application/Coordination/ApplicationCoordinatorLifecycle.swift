import LittleSwitchCommon
import LittleSwitchCore
import OSLog

public enum ApplicationShutdownMode: Sendable, Equatable {
    case userQuit
    case handoff
}

extension ApplicationCoordinator {
    public func connect() async throws -> CoordinatorSnapshot {
        let routing = routingSnapshot()
        guard routing.hasValidMapping else {
            throw Error.noMappedModel
        }

        try await startGateway(snapshot: routing)
        do {
            // Trust settles before the profile is written: the Desktop
            // reads the origin we advertise literally, so https only goes
            // in once the leaf is actually trusted — otherwise the profile
            // keeps the plain-http origin and stays functional.
            let trust = tlsProvisioner?.installTrust(secretStore: secretStore)
            report(trust?.failures ?? [], during: "connect")
            let tlsReady = trust?.isTrusted ?? false
            try profileManager.activate(
                autoMode: configuration.autoMode,
                tlsEnabled: tlsReady
            )
            configuration.connected = true
            try configurationStore.save(configuration)
            await claudeController.relaunch()
        } catch {
            try? profileManager.restore()
            configuration.connected = false
            try? configurationStore.save(configuration)
            throw error
        }
        return await snapshot()
    }

    public func disconnect() async throws -> CoordinatorSnapshot {
        try profileManager.restore()
        // The trust anchor deliberately survives the toggle: the authority's
        // signing key is destroyed at issuance, so a lingering anchor cannot
        // vouch for anything that does not already exist — removing it would
        // only force the consent prompt back on every reconnect.
        configuration.connected = false
        // The disconnect confirm names the discarded drafts, so the mapping
        // draft cannot outlive the connection it drafts against.
        pendingClaudeMappings = nil
        try configurationStore.save(configuration)
        await claudeController.relaunch()
        return await snapshot()
    }

    public func shutdown(mode: ApplicationShutdownMode = .userQuit) async {
        pendingCodexSettings = nil
        pendingClaudeCodeSettings = nil
        pendingOpenCodeSettings = nil
        pendingWebSearchSettings = nil
        pendingMonitoringSettings = nil
        pendingClaudeMappings = nil
        for operation in providerRefreshOperations.values {
            operation.task.cancel()
        }
        providerRefreshOperations.removeAll()
        suspendImageInputProbes()
        await imageInputRegistry.shutdown()
        await imageProbeAdmission.bind(nil)
        await credentialRefresher.cancelAll()
        await stopGateway()
        await monitoringExporter.shutdown()
        switch mode {
        case .userQuit:
            let targets = RelaunchTargets(
                claude: configuration.connected,
                codex: configuration.codex.connected,
                claudeCode: configuration.claudeCode.connected,
                openCode: configuration.openCode.connected
            )
            if configuration.relaunchTargets != targets {
                configuration.relaunchTargets = targets
                try? configurationStore.save(configuration)
            }
            if configuration.connected {
                try? profileManager.restore()
                configuration.connected = false
                try? configurationStore.save(configuration)
            }
            if configuration.codex.connected {
                try? codexProfileManager?.restore()
                configuration.codex.connected = false
                appliedCodexState = .disconnected
                try? configurationStore.save(configuration)
            }
            if configuration.claudeCode.connected {
                try? claudeCodeProfileManager?.restore()
                configuration.claudeCode.connected = false
                appliedClaudeCodeSettings = nil
                claudeCodeStatus = .disconnected
                try? configurationStore.save(configuration)
            }
            if configuration.openCode.connected {
                try? openCodeProfileManager?.restore()
                configuration.openCode.connected = false
                appliedOpenCodeSettings = nil
                openCodeStatus = .disconnected
                try? configurationStore.save(configuration)
            }
        case .handoff:
            break
        }
        try? await discoveryTransport.shutdown()
    }
}

extension ApplicationCoordinator {
    /// Writes out what the trust store refused.
    ///
    /// `LittleSwitchCore` does not log, by design, so a Security.framework
    /// status is only ever readable here. It has to be: the framework
    /// answers synchronously and the installer already names the call that
    /// failed, so a trust anchor that never installs is diagnosable in the
    /// first second — but only if the status is written down. A run that
    /// discards it looks exactly like a user declining the prompt.
    ///
    /// Nothing here is secret: an `OSStatus` and the framework's own
    /// message for it, never key material or the certificate itself.
    private func report(_ failures: [GatewayTLSTrustFailure], during stage: String) {
        for failure in failures {
            let reason = failure.description
            Self.tlsLogger.error(
                "Gateway TLS trust failed on \(stage, privacy: .public): \(reason, privacy: .public)"
            )
        }
    }

    private static let tlsLogger = Logger(
        subsystem: ProductIdentity.logSubsystem,
        category: "gateway-tls"
    )
}
