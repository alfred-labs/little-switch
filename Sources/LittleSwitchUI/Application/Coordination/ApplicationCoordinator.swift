import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchTransport

// The coordinator's stored state and wiring stay in one file while the
// usage-dashboard work lands; the TLS additions tipped it past the gate.
// swiftlint:disable file_length

public actor ApplicationCoordinator {
    package let monitoringExporter: MonitoringExportService
    package var pendingMonitoringSettings: MonitoringPendingSettings?
    package var monitoringDraftGeneration: UInt64 = 0
    package var monitoringSnapshotSequence: UInt64 = 0
    package var monitoringApplyInProgress = false
    package var monitoringTestInProgress = false
    package var gatewayHasTLSIdentity = false
    package var monitoringNotice: String?
    package var monitoringTestResult: MonitoringExportTestResult?
    package var configuration: AppConfiguration
    package let configurationStore: any ConfigurationStoring
    package let secretStore: any SecretStore
    /// The gateway TLS footprint; nil leaves the listener plain-HTTP only.
    package let tlsProvisioner: (any GatewayTLSProvisioning)?
    package let profileManager: any ClaudeProfileManaging
    package let claudeController: any ClaudeApplicationControlling
    package let codexProfileManager: (any CodexProfileManaging)?
    package let codexController: (any CodexApplicationControlling)?
    package let claudeCodeProfileManager: (any ClaudeCodeProfileManaging)?
    package let openCodeProfileManager: (any OpenCodeProfileManaging)?
    package let discoveryTransport: any UpstreamTransport
    package let credentialScriptRunner: any CredentialScriptRunning
    package let credentialRefresher: CredentialRefresher
    private let gatewayTransportBuilder: any GatewayTransportBuilding
    package let providerClient: ProviderClient
    package let providerWireProber: any ProviderWireProbing
    private let gatewayListenPort: Int
    private let gatewayRequiredAuthorityPort: Int?
    private let gatewayServerOverride: (any GatewayServing)?
    private let gatewayStateOverride: GatewayState?
    /// Owned for the coordinator's whole lifetime so learned Responses
    /// verdicts ride gateway restarts: each start hands the same ledger to
    /// the freshly built gateway state. Package-visible so provider saves
    /// can seed it from the save-time endpoint probe.
    package let responsesCapabilities: ResponsesCapabilityLedger
    package let gatewayRoutingMutationGuard: GatewayRoutingMutationGuard
    private let gatewayFactory: any GatewayFactory
    private let gatewayStartupObserver: any GatewayStartupObserving
    private let trafficRecorder: any TrafficRecording
    package var providerRefreshOperations: [UUID: ProviderRefreshOperation] = [:]
    package var providerIntentGeneration: UInt64 = 0
    package var providerIntents: [UUID: UInt64] = [:]
    package var gatewayState: GatewayState?
    var gatewayServer: (any GatewayServing)?
    var gatewayStartup: GatewayStartup?
    private var gatewayStartupWaiters: Set<UUID> = []
    private var gatewayStop: GatewayStop?
    var gatewayLifecycleGeneration: UInt64 = 0
    var gatewayActivityStartingCount = 0
    private var gatewayStopEpoch: UInt64 = 0
    package var pendingCodexSettings: CodexSettingsDraft?
    package var appliedCodexState = AppliedCodexState.disconnected
    /// Route mappings edited while connected, waiting for Apply. The draft
    /// is a full replacement of the applied mappings: routes absent from it
    /// read as unassigned.
    package var pendingClaudeMappings: [String: ModelMapping]?
    package var pendingClaudeCodeSettings: ClaudeCodeSettingsDraft?
    package var appliedClaudeCodeSettings: ClaudeCodeManagedSettings?
    package var claudeCodeStatus: ClaudeCodeConnectionStatus = .disconnected
    package var pendingOpenCodeSettings: OpenCodeSettingsDraft?
    /// Web search edits waiting for Apply. The other panes keep their drafts
    /// here too, so leaving a section no longer decides whether work survives.
    package var pendingWebSearchSettings: WebSearchInput?
    package var appliedOpenCodeSettings: OpenCodeManagedSettings?
    package var openCodeStatus: OpenCodeConnectionStatus = .disconnected

    public init(
        configurationStore: any ConfigurationStoring,
        secretStore: any SecretStore,
        profileManager: any ClaudeProfileManaging,
        claudeController: any ClaudeApplicationControlling,
        codexProfileManager: (any CodexProfileManaging)? = nil,
        codexController: (any CodexApplicationControlling)? = nil,
        claudeCodeProfileManager: (any ClaudeCodeProfileManaging)? = nil,
        openCodeProfileManager: (any OpenCodeProfileManaging)? = nil,
        discoveryTransport: any UpstreamTransport = AsyncHTTPTransport(),
        gatewayTransport: any UpstreamTransport = AsyncHTTPTransport(),
        gatewayListenPort: Int = 11_436,
        gatewayRequiredAuthorityPort: Int? = 11_436,
        gatewayServerOverride: (any GatewayServing)? = nil,
        gatewayStateOverride: GatewayState? = nil,
        responsesCapabilities: ResponsesCapabilityLedger = ResponsesCapabilityLedger(),
        gatewayBuilder: any GatewayBuilding = LiveGatewayBuilder(),
        trafficRecorder: any TrafficRecording = NoopTrafficRecorder(),
        credentialScriptRunner: any CredentialScriptRunning = ProcessCredentialScriptRunner(),
        credentialRefresher: CredentialRefresher? = nil,
        tlsProvisioner: (any GatewayTLSProvisioning)? = nil,
        monitoringExporter: MonitoringExportService? = nil
    ) {
        self.configurationStore = configurationStore
        self.secretStore = secretStore
        self.tlsProvisioner = tlsProvisioner
        self.monitoringExporter = monitoringExporter ?? MonitoringExportService(store: MonitoringStore())
        self.profileManager = profileManager
        self.claudeController = claudeController
        self.codexProfileManager = codexProfileManager
        self.codexController = codexController
        self.claudeCodeProfileManager = claudeCodeProfileManager
        self.openCodeProfileManager = openCodeProfileManager
        self.discoveryTransport = discoveryTransport
        self.credentialScriptRunner = credentialScriptRunner
        self.credentialRefresher =
            credentialRefresher
            ?? CredentialRefresher(
                secretStore: secretStore,
                runner: credentialScriptRunner
            )
        gatewayTransportBuilder = InjectedGatewayTransportBuilder(transport: gatewayTransport)
        self.gatewayListenPort = gatewayListenPort
        self.gatewayRequiredAuthorityPort = gatewayRequiredAuthorityPort
        self.gatewayServerOverride = gatewayServerOverride
        self.gatewayStateOverride = gatewayStateOverride
        gatewayRoutingMutationGuard =
            gatewayStateOverride?.routingMutationGuard ?? GatewayRoutingMutationGuard()
        self.responsesCapabilities = responsesCapabilities
        gatewayFactory = LiveGatewayFactory(builder: gatewayBuilder)
        gatewayStartupObserver = LiveGatewayStartupObserver()
        self.trafficRecorder = trafficRecorder
        providerClient = ProviderClient(transport: discoveryTransport)
        providerWireProber = ProviderWireProber(transport: discoveryTransport)
        configuration = AppConfiguration()
    }

    package init(
        configurationStore: any ConfigurationStoring,
        secretStore: any SecretStore,
        profileManager: any ClaudeProfileManaging,
        claudeController: any ClaudeApplicationControlling,
        codexProfileManager: (any CodexProfileManaging)? = nil,
        codexController: (any CodexApplicationControlling)? = nil,
        claudeCodeProfileManager: (any ClaudeCodeProfileManaging)? = nil,
        openCodeProfileManager: (any OpenCodeProfileManaging)? = nil,
        discoveryTransport: any UpstreamTransport = AsyncHTTPTransport(),
        gatewayTransportBuilder: any GatewayTransportBuilding,
        gatewayListenPort: Int = 11_436,
        gatewayRequiredAuthorityPort: Int? = 11_436,
        gatewayServerOverride: (any GatewayServing)? = nil,
        gatewayStateOverride: GatewayState? = nil,
        responsesCapabilities: ResponsesCapabilityLedger = ResponsesCapabilityLedger(),
        gatewayFactory: any GatewayFactory,
        gatewayStartupObserver: any GatewayStartupObserving = LiveGatewayStartupObserver(),
        trafficRecorder: any TrafficRecording = NoopTrafficRecorder(),
        credentialScriptRunner: any CredentialScriptRunning = ProcessCredentialScriptRunner(),
        credentialRefresher: CredentialRefresher? = nil,
        tlsProvisioner: (any GatewayTLSProvisioning)? = nil,
        monitoringExporter: MonitoringExportService? = nil,
        providerWireProber: (any ProviderWireProbing)? = nil
    ) {
        self.configurationStore = configurationStore
        self.secretStore = secretStore
        self.tlsProvisioner = tlsProvisioner
        self.monitoringExporter = monitoringExporter ?? MonitoringExportService(store: MonitoringStore())
        self.profileManager = profileManager
        self.claudeController = claudeController
        self.codexProfileManager = codexProfileManager
        self.codexController = codexController
        self.claudeCodeProfileManager = claudeCodeProfileManager
        self.openCodeProfileManager = openCodeProfileManager
        self.discoveryTransport = discoveryTransport
        self.credentialScriptRunner = credentialScriptRunner
        self.credentialRefresher =
            credentialRefresher
            ?? CredentialRefresher(
                secretStore: secretStore,
                runner: credentialScriptRunner
            )
        self.gatewayTransportBuilder = gatewayTransportBuilder
        self.gatewayListenPort = gatewayListenPort
        self.gatewayRequiredAuthorityPort = gatewayRequiredAuthorityPort
        self.gatewayServerOverride = gatewayServerOverride
        self.gatewayStateOverride = gatewayStateOverride
        gatewayRoutingMutationGuard =
            gatewayStateOverride?.routingMutationGuard ?? GatewayRoutingMutationGuard()
        self.responsesCapabilities = responsesCapabilities
        self.gatewayFactory = gatewayFactory
        self.gatewayStartupObserver = gatewayStartupObserver
        self.trafficRecorder = trafficRecorder
        providerClient = ProviderClient(transport: discoveryTransport)
        self.providerWireProber = providerWireProber ?? ProviderWireProber(transport: discoveryTransport)
        configuration = AppConfiguration()
    }

    public func snapshot() async -> CoordinatorSnapshot {
        reconcileCodexDraft()
        reconcileOpenCodeDraft()
        // The mapping draft reconciles first: the Claude Code draft below
        // reconciles against the mappings it merges in.
        reconcileClaudeMappingsDraft()
        reconcileClaudeCodeDraft()
        let count = await gatewayState?.sessionRequestCount ?? 0
        let claudeCount = await gatewayState?.claudeSessionRequestCount ?? 0
        let codexCount = await gatewayState?.codexSessionRequestCount ?? 0
        let proxyRunning = await gatewayServer?.isRunning ?? false
        let refreshFailures = await credentialRefresher.failureMessages()
        let scriptOutputs = await credentialRefresher.lastScriptOutputs()
        let monitoringStatus = await monitoringStatusSnapshot()
        monitoringSnapshotSequence &+= 1
        var effectiveConfiguration = configuration
        if let pendingClaudeMappings {
            effectiveConfiguration.mappings = pendingClaudeMappings
        }
        effectiveConfiguration =
            pendingCodexSettings?.applying(to: effectiveConfiguration)
            ?? effectiveConfiguration
        effectiveConfiguration =
            pendingClaudeCodeSettings?.applying(to: effectiveConfiguration)
            ?? effectiveConfiguration
        if effectiveConfiguration.openCode.connected || pendingOpenCodeSettings != nil {
            effectiveConfiguration.openCode = effectiveConfiguration.openCode.normalized(
                providers: effectiveConfiguration.providers,
                codex: effectiveConfiguration.codex
            )
        }
        effectiveConfiguration =
            pendingOpenCodeSettings?.applying(to: effectiveConfiguration)
            ?? effectiveConfiguration
        return CoordinatorSnapshot(
            configuration: effectiveConfiguration,
            requestCount: count,
            claudeRequestCount: claudeCount,
            codexRequestCount: codexCount,
            proxyRunning: proxyRunning,
            hasPendingCodexChanges: hasPendingCodexChanges,
            hasPendingClaudeMappings: hasPendingClaudeMappings,
            claudeCodeStatus: claudeCodeStatus,
            hasPendingClaudeCodeChanges: hasPendingClaudeCodeChanges,
            // The route list follows the same effective view as the
            // mappings above: the Claude Code pane drafts with the pending
            // remaps, not against the applied set they will replace.
            claudeCodeMappedRouteIDs: effectiveConfiguration.claudeCode.mappedRouteIDs(
                providers: effectiveConfiguration.providers,
                mappings: effectiveConfiguration.mappings
            ),
            openCodeStatus: openCodeStatus,
            hasPendingOpenCodeChanges: hasPendingOpenCodeChanges,
            webSearchDraft: pendingWebSearchSettings,
            monitoringDraft: pendingMonitoringSettings,
            monitoringStatus: monitoringStatus,
            monitoringApplying: monitoringApplyInProgress,
            monitoringNotice: monitoringNotice,
            monitoringTestResult: monitoringTestResult,
            monitoringHTTPSAvailable: proxyRunning && gatewayHasTLSIdentity
                && tlsProvisioner?.isTrusted(secretStore: secretStore) == true,
            monitoringSnapshotSequence: monitoringSnapshotSequence,
            credentialRefreshFailures: refreshFailures,
            lastScriptOutputs: scriptOutputs
        )
    }
}

extension ApplicationCoordinator {
    package func startGateway(snapshot: RoutingSnapshot) async throws {
        try Task.checkCancellation()
        if let gatewayStop {
            guard gatewayStop.permitsRestart else {
                throw CancellationError()
            }
            let stopEpoch = gatewayStopEpoch
            await gatewayStartupObserver.waitingForAbandonedStartupCleanup()
            await gatewayStop.task.value
            finishGatewayStop(gatewayStop)
            try Task.checkCancellation()
            guard gatewayStopEpoch == stopEpoch else {
                throw CancellationError()
            }
            try await startGateway(snapshot: snapshot)
            return
        }
        if let gatewayServer {
            let generation = gatewayLifecycleGeneration
            let stopEpoch = gatewayStopEpoch
            let state = gatewayState
            let isRunning = await gatewayServer.isRunning
            try Task.checkCancellation()
            guard
                generation == gatewayLifecycleGeneration,
                self.gatewayState === state
            else {
                guard gatewayStopEpoch == stopEpoch else {
                    throw CancellationError()
                }
                try await startGateway(snapshot: snapshot)
                return
            }
            guard !isRunning else {
                return
            }

            gatewayActivityStartingCount += 1
            defer { gatewayActivityStartingCount -= 1 }
            let stop = beginDeadGatewayCleanup(gatewayServer)
            await stop.task.value
            finishGatewayStop(stop)
            try Task.checkCancellation()
            guard gatewayStopEpoch == stopEpoch else {
                throw CancellationError()
            }
            try await startGateway(snapshot: snapshot)
            return
        }
        if let gatewayStartup {
            let waiterID = UUID()
            gatewayStartupWaiters.insert(waiterID)
            try await awaitGatewayStartup(
                gatewayStartup,
                waiterID: waiterID,
                joined: true
            )
            return
        }

        gatewayLifecycleGeneration &+= 1
        let generation = gatewayLifecycleGeneration
        let startupState =
            gatewayStateOverride
            ?? GatewayState(
                snapshot: snapshot,
                routingMutationGuard: gatewayRoutingMutationGuard,
                responsesCapabilities: responsesCapabilities
            )
        let operation = GatewayStartupOperation(
            state: startupState,
            transportBuilder: gatewayTransportBuilder,
            serverOverride: gatewayServerOverride,
            factory: gatewayFactory,
            secretStore: secretStore,
            listenPort: gatewayListenPort,
            requiredAuthorityPort: gatewayRequiredAuthorityPort,
            trafficRecorder: trafficRecorder,
            tlsIdentity: tlsProvisioner?.identity(secretStore: secretStore),
            monitoring: gatewayMonitoring
        )
        let startup = GatewayStartup(
            generation: generation,
            state: startupState,
            task: Task {
                await monitoringExporter.updateProviderPool(startupState)
                return try await operation.run()
            }
        )
        gatewayStartup = startup
        let waiterID = UUID()
        gatewayStartupWaiters = [waiterID]
        try await awaitGatewayStartup(
            startup,
            waiterID: waiterID,
            joined: false
        )
    }

    private func awaitGatewayStartup(
        _ startup: GatewayStartup,
        waiterID: UUID,
        joined: Bool
    ) async throws {
        try await withTaskCancellationHandler {
            try await awaitGatewayStartupValue(
                startup,
                waiterID: waiterID,
                joined: joined
            )
        } onCancel: {
            Task {
                await self.gatewayStartupObserver.cancellingStartupWaiter()
                await self.cancelGatewayStartupWaiter(
                    waiterID,
                    generation: startup.generation
                )
                await self.gatewayStartupObserver.cancelledStartupWaiter()
            }
        }
    }

    private func awaitGatewayStartupValue(
        _ startup: GatewayStartup,
        waiterID: UUID,
        joined: Bool
    ) async throws {
        do {
            if joined {
                await gatewayStartupObserver.joinedStartup()
                try Task.checkCancellation()
            }
            let result = try await startup.task.value
            await gatewayStartupObserver.readyToPublishStartup()
            try Task.checkCancellation()
            guard
                gatewayLifecycleGeneration == startup.generation,
                gatewayStop == nil
            else {
                throw CancellationError()
            }
            gatewayStartupWaiters.remove(waiterID)
            if gatewayServer == nil {
                gatewayState = result.state
                gatewayServer = result.server
                gatewayHasTLSIdentity = result.hasTLSIdentity
            }
            if gatewayStartup?.generation == startup.generation {
                gatewayStartup = nil
                gatewayStartupWaiters.removeAll()
            }
        } catch {
            gatewayStartupWaiters.remove(waiterID)
            let ownsStartup =
                gatewayStartup?.generation == startup.generation
                && gatewayStop == nil
            let isLastWaiter = gatewayStartupWaiters.isEmpty
            if ownsStartup && isLastWaiter {
                await discardGatewayStartup(startup)
            } else if let gatewayStop {
                if gatewayStop.startupGeneration == startup.generation {
                    await gatewayStop.task.value
                    finishGatewayStop(gatewayStop)
                }
            }
            try Task.checkCancellation()
            throw error
        }
    }

    private func cancelGatewayStartupWaiter(
        _ waiterID: UUID,
        generation: UInt64
    ) {
        guard let startup = gatewayStartup, startup.generation == generation else {
            return
        }
        let removed = gatewayStartupWaiters.remove(waiterID) != nil
        guard removed, gatewayStartupWaiters.isEmpty, gatewayStop == nil else {
            return
        }
        _ = beginGatewayStartupDiscard(startup)
    }

    private func discardGatewayStartup(_ startup: GatewayStartup) async {
        let stop = beginGatewayStartupDiscard(startup)
        await stop.task.value
        finishGatewayStop(stop)
    }

    private func beginGatewayStartupDiscard(_ startup: GatewayStartup) -> GatewayStop {
        gatewayLifecycleGeneration &+= 1
        startup.task.cancel()
        let stop = GatewayStop(
            generation: gatewayLifecycleGeneration,
            startupGeneration: startup.generation,
            permitsRestart: true,
            task: Task {
                if let result = try? await startup.task.value {
                    await cleanupGatewayServer(
                        result.server,
                        transport: result.transport
                    )
                }
            }
        )
        gatewayStop = stop
        return stop
    }

    private func beginDeadGatewayCleanup(
        _ server: any GatewayServing
    ) -> GatewayStop {
        gatewayLifecycleGeneration &+= 1
        gatewayServer = nil
        gatewayState = nil
        let stop = GatewayStop(
            generation: gatewayLifecycleGeneration,
            startupGeneration: nil,
            permitsRestart: true,
            task: Task {
                await cleanupGatewayServer(server, transport: nil)
            }
        )
        gatewayStop = stop
        return stop
    }

    package func stopGateway() async {
        gatewayStopEpoch &+= 1
        if let gatewayStop {
            let explicitStop: GatewayStop
            if gatewayStop.permitsRestart {
                gatewayLifecycleGeneration &+= 1
                explicitStop = GatewayStop(
                    generation: gatewayLifecycleGeneration,
                    startupGeneration: gatewayStop.startupGeneration,
                    permitsRestart: false,
                    task: gatewayStop.task
                )
                self.gatewayStop = explicitStop
            } else {
                explicitStop = gatewayStop
            }
            await gatewayStartupObserver.stoppingAbandonedStartup()
            await explicitStop.task.value
            finishGatewayStop(explicitStop)
            return
        }

        gatewayLifecycleGeneration &+= 1
        let stopGeneration = gatewayLifecycleGeneration
        let startup = gatewayStartup
        let runningServer = gatewayServer
        startup?.task.cancel()
        gatewayServer = nil
        gatewayState = nil
        let stop = GatewayStop(
            generation: stopGeneration,
            startupGeneration: startup?.generation,
            permitsRestart: false,
            task: Task {
                if let startup {
                    if let result = try? await startup.task.value {
                        await cleanupGatewayServer(
                            result.server,
                            transport: result.transport
                        )
                    }
                }
                if let runningServer {
                    await cleanupGatewayServer(runningServer, transport: nil)
                }
            }
        )
        gatewayStop = stop
        await stop.task.value
        finishGatewayStop(stop)
    }

    private func finishGatewayStop(_ stop: GatewayStop) {
        guard gatewayStop?.generation == stop.generation else {
            return
        }
        if gatewayStartup?.generation == stop.startupGeneration {
            gatewayStartup = nil
        }
        gatewayStartupWaiters.removeAll()
        gatewayStop = nil
    }
}
