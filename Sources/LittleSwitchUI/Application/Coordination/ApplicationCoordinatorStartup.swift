import Foundation
import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    public func start() async throws -> CoordinatorSnapshot {
        isShuttingDown = false
        gatewayActivityStartingCount += 1
        defer { gatewayActivityStartingCount -= 1 }
        configuration = try configurationStore.load()
        await initializeImageInputProbing()
        for provider in configuration.providers { await synchronizeImageInputContext(providerID: provider.id) }
        await startMonitoring()
        await seedPersistedWireProbes()
        await refreshProvidersAtStartup()
        await scheduleCredentialRefreshesAtStartup()
        let routing = routingSnapshot()
        do {
            try await startGateway(snapshot: routing)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Error.gatewayUnavailable
        }
        if configuration.connected {
            // An unreadable profile is not evidence that ownership was lost.
            // Keep restoration responsibility until the check succeeds.
            let profileIsActive = try profileManager.isActive(autoMode: configuration.autoMode)
            if !routing.hasValidMapping || !profileIsActive {
                if profileIsActive { try profileManager.restore() }
                var disconnected = configuration
                disconnected.connected = false
                try configurationStore.save(disconnected)
                configuration = disconnected
                appliedClaudeDesktopCatalog = nil
            } else {
                let catalog = claudeDesktopCatalog(in: configuration)
                appliedClaudeDesktopCatalog = try profileManager.catalogMatches(catalog) ? catalog : nil
            }
        }
        _ = await responsesWireVerdicts()
        if configuration.codex.connected {
            let hasModels =
                !configuration.codex.exposedModels(in: configuration.providers).isEmpty
            let expectedSignature: CodexManagedProfileSignature?
            if hasModels {
                expectedSignature = try? CodexManagedProfileSignature.resolve(
                    providers: configuration.providers,
                    configuration: configuration.codex,
                    responsesWireVerdicts: catalogResponsesWireVerdicts
                )
            } else {
                expectedSignature = nil
            }
            let profileStatus: CodexProfileStatus?
            if let expectedSignature, let codexProfileManager {
                profileStatus = try? codexProfileManager.status(
                    providers: configuration.providers,
                    configuration: configuration.codex,
                    expected: expectedSignature
                )
            } else {
                profileStatus = nil
            }
            if let expectedSignature {
                switch profileStatus {
                case .active(let active) where active == expectedSignature:
                    appliedCodexState = .connected(
                        AppliedCodexSnapshot(
                            configuration: configuration.codex,
                            providers: configuration.providers,
                            signature: active
                        )
                    )
                case .requiresUpdate(let applied):
                    appliedCodexState = .connected(
                        AppliedCodexSnapshot(
                            configuration: configuration.codex,
                            providers: configuration.providers,
                            signature: applied
                        )
                    )
                default:
                    configuration.codex.connected = false
                    try configurationStore.save(configuration)
                }
            } else {
                configuration.codex.connected = false
                try configurationStore.save(configuration)
            }
        }
        try initializeClaudeCodeStatus()
        try initializeOpenCodeStatus()
        await reconnectRelaunchTargets()
        return await snapshot()
    }

    /// Replays persisted probes into the in-memory ledger at launch, so the
    /// first request after a relaunch skips the discovery 404 it already
    /// paid for at save time — the persisted `wireProbe` would otherwise be
    /// write-only for routing. Negative evidence only, matching the save
    /// path: a probe "available" is display evidence, never routing
    /// evidence.
    private func seedPersistedWireProbes() async {
        for provider in configuration.providers
        where provider.wireProbe?.responsesRouteAbsent == true {
            await responsesCapabilities.record(
                providerID: provider.id,
                supportsNative: false
            )
        }
    }

    private func refreshProvidersAtStartup() async {
        let providerIDs = configuration.providers.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for providerID in providerIDs {
                group.addTask { [self] in
                    _ = try? await refreshProvider(id: providerID)
                }
            }
        }
    }

    /// Script credentials resume their cadence at launch; providers without a
    /// stored token refresh immediately so they become usable right away,
    /// while a still-valid keychain token waits out its full period. A read
    /// that fails (locked keychain, transient securityd error) reads as
    /// "a token exists": firing the script at launch over it would run
    /// interactive logins unprompted, and the next cycle picks the real
    /// state up. The reads are independent, so they run concurrently —
    /// securityd round-trips are serial otherwise and every one delays the
    /// gateway's start.
    private func scheduleCredentialRefreshesAtStartup() async {
        let scriptProviders = configuration.providers.filter { $0.credentialSource == .script }
        let immediateProviderIDs: Set<UUID> = await withTaskGroup(
            of: (UUID, Bool).self
        ) { group in
            for provider in scriptProviders {
                group.addTask { [secretStore] in
                    let refreshesImmediately: Bool
                    do {
                        refreshesImmediately =
                            try secretStore.read(providerID: provider.id) == nil
                    } catch {
                        refreshesImmediately = false
                    }
                    return (provider.id, refreshesImmediately)
                }
            }
            var immediate: Set<UUID> = []
            for await (providerID, refreshesImmediately) in group where refreshesImmediately {
                immediate.insert(providerID)
            }
            return immediate
        }
        for provider in scriptProviders {
            await credentialRefresher.schedule(
                providerID: provider.id,
                interval:
                    provider.credentialRefreshInterval
                    ?? Provider.defaultCredentialRefreshInterval,
                immediate: immediateProviderIDs.contains(provider.id),
                scriptPath: provider.credentialScriptPath ?? ""
            )
        }
    }
}
