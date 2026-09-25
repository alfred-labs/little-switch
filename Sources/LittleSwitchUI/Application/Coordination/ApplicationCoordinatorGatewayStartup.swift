import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchTransport

struct GatewayStartup: Sendable {
    let generation: UInt64
    let state: GatewayState
    let task: Task<GatewayStartupResult, any Swift.Error>
}

struct GatewayStop: Sendable {
    let generation: UInt64
    let startupGeneration: UInt64?
    let permitsRestart: Bool
    let task: Task<Void, Never>
}

struct GatewayStartupResult: Sendable {
    let state: GatewayState
    let server: any GatewayServing
    let transport: ShutdownOnceUpstreamTransport?
    var hasTLSIdentity = false
}

struct GatewayStartupOperation: Sendable {
    let state: GatewayState
    let transportBuilder: any GatewayTransportBuilding
    let serverOverride: (any GatewayServing)?
    let factory: any GatewayFactory
    let secretStore: any SecretStore
    let listenPort: Int
    let requiredAuthorityPort: Int?
    let trafficRecorder: any TrafficRecording
    let tlsIdentity: GatewayTLSIdentity?
    var monitoring: GatewayMonitoring?

    func run() async throws -> GatewayStartupResult {
        try Task.checkCancellation()
        let server: any GatewayServing
        let ownedTransport: ShutdownOnceUpstreamTransport?
        if let serverOverride {
            server = serverOverride
            ownedTransport = nil
        } else {
            let upstream = await transportBuilder.makeTransport()
            let transport = ShutdownOnceUpstreamTransport(upstream: upstream)
            ownedTransport = transport
            do {
                try Task.checkCancellation()
                server = try factory.makeGateway(
                    GatewayBuildContext(
                        state: state,
                        transport: transport,
                        secretStore: secretStore,
                        listenPort: listenPort,
                        requiredAuthorityPort: requiredAuthorityPort,
                        trafficRecorder: trafficRecorder,
                        tlsIdentity: tlsIdentity,
                        monitoring: monitoring
                    )
                )
                try Task.checkCancellation()
            } catch {
                await cleanupGatewayTransport(transport)
                try Task.checkCancellation()
                throw error
            }
        }

        do {
            try Task.checkCancellation()
            try await server.start()
            try Task.checkCancellation()
        } catch {
            await cleanupGatewayServer(server, transport: ownedTransport)
            try Task.checkCancellation()
            throw error
        }
        return GatewayStartupResult(
            state: state,
            server: server,
            transport: ownedTransport,
            hasTLSIdentity: tlsIdentity != nil
        )
    }
}

func cleanupGatewayTransport(_ transport: any UpstreamTransport) async {
    let cleanupTask = Task {
        try? await transport.shutdown()
    }
    await cleanupTask.value
}

func cleanupGatewayServer(
    _ server: any GatewayServing,
    transport: (any UpstreamTransport)?
) async {
    let cleanupTask = Task {
        await server.stop()
        try? await transport?.shutdown()
    }
    await cleanupTask.value
}

extension ApplicationCoordinator {
    package func gatewayRoutingSnapshot(
        for configuration: AppConfiguration
    ) -> RoutingSnapshot {
        RoutingSnapshot(
            generation: (gatewayState == nil ? 0 : 1),
            providers: configuration.providers,
            mappings: configuration.mappings,
            codex: configuration.codex,
            chatgpt: configuration.chatgpt,
            webSearch: configuration.webSearch,
            modelIndicator: configuration.modelIndicator
        )
    }

    package func routingSnapshot() -> RoutingSnapshot {
        gatewayRoutingSnapshot(for: applyingDesktopRouting(to: configuration))
    }

    package func replaceGatewayRoutingIfNeeded(
        credentialChangedProviderIDs: Set<UUID> = []
    ) async {
        // The ledger survives gateway shutdown too; credential changes while
        // stopped must not resurrect old evidence at the next start.
        if !credentialChangedProviderIDs.isEmpty {
            await customToolCapabilities?.invalidate(providerIDs: credentialChangedProviderIDs)
        }
        var states: [GatewayState] = []
        if let gatewayState {
            states.append(gatewayState)
        }
        let startupState = gatewayStartup?.state
        if let startupState, !states.contains(where: { $0 === startupState }) {
            states.append(startupState)
        }
        for state in states {
            let configuration = applyingDesktopRouting(to: configuration)
            await state.replace(
                providers: configuration.providers,
                mappings: configuration.mappings,
                codex: configuration.codex,
                chatgpt: configuration.chatgpt,
                webSearch: configuration.webSearch,
                modelIndicator: configuration.modelIndicator,
                credentialChangedProviderIDs: credentialChangedProviderIDs
            )
        }
    }
}
