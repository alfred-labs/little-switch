import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchUI

@Suite("Application coordinator responses wire")
struct ApplicationCoordinatorResponsesWireTests {
    @Test("Verdicts surface from the attached gateway state only")
    @MainActor
    func verdictsSurface() async throws {
        let fixture = gatewayActivityFixture()
        let providerID = fixture.provider.id
        await fixture.state.responsesCapabilities.record(
            providerID: providerID,
            supportsNative: true
        )

        // A coordinator that never started has no gateway state to read.
        let idle = makeGatewayActivityCoordinator(
            state: fixture.state,
            server: TestGatewayServer()
        )
        #expect(await idle.responsesWireVerdicts().isEmpty)

        let discoveryTransport = SuspendedCatalogTransport()
        let running = makeGatewayActivityCoordinator(
            configuration: AppConfiguration(providers: [fixture.provider]),
            discoveryTransport: discoveryTransport,
            state: fixture.state,
            server: TestGatewayServer()
        )
        let startup = Task {
            try await running.start()
        }
        defer {
            startup.cancel()
            Task { await discoveryTransport.releaseExecute() }
        }
        try await discoveryTransport.waitUntilExecuteWasCalled()
        await discoveryTransport.releaseExecute()
        _ = try? await valueWithinTimeout(
            startup,
            description: "startup so the gateway state attaches"
        )

        let verdicts = await running.responsesWireVerdicts()
        #expect(verdicts[providerID] == true)
        await running.stopGateway()
    }

    @Test("Learned Responses verdicts survive a gateway restart")
    @MainActor
    func verdictsSurviveRestart() async throws {
        let providerID = UUID()
        let snapshot = RoutingSnapshot(
            generation: 1,
            providers: [
                Provider(
                    id: providerID,
                    name: "Native",
                    baseURL: "https://example.com/api",
                    authMode: .bearer,
                    models: [
                        DiscoveredModel(id: "native-model", maxTokens: 8_192, detectedContextWindow: nil)
                    ]
                )
            ],
            mappings: [:],
            codex: CodexConfiguration()
        )
        let capabilities = ResponsesCapabilityLedger()
        let coordinator = ApplicationCoordinator(
            configurationStore: RecordingConfigurationStore(configuration: AppConfiguration()),
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            responsesCapabilities: capabilities
        )

        try await coordinator.startGateway(snapshot: snapshot)
        await capabilities.record(providerID: providerID, supportsNative: false)
        #expect(await coordinator.responsesWireVerdicts()[providerID] == false)

        await coordinator.stopGateway()
        #expect(await coordinator.responsesWireVerdicts().isEmpty)

        try await coordinator.startGateway(snapshot: snapshot)
        // The learned verdict rides the restart: the settings row stays on
        // its resolved wire and the first request skips the native probe.
        #expect(await coordinator.responsesWireVerdicts()[providerID] == false)
        await coordinator.stopGateway()
    }

    @Test("Saving a provider probes its routes and seeds the Responses ledger")
    @MainActor
    func saveProbesRoutesAndSeedsLedger() async throws {
        let transport = WireProbingCatalogTransport()
        let store = ScriptedConfigurationStore(configuration: AppConfiguration())
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: transport,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            responsesCapabilities: ResponsesCapabilityLedger()
        )
        _ = try await coordinator.startGateway(
            snapshot: RoutingSnapshot(generation: 1, providers: [], mappings: [:])
        )

        _ = try await coordinator.saveProvider(
            ProviderInput(
                name: "Chat Only",
                baseURL: "https://example.com/api",
                authMode: .bearer,
                credential: "probe-secret",
                responsesWireOverride: .chatCompletions
            )
        )

        let saved = try #require(store.configuration.providers.first)
        #expect(saved.responsesWireOverride == .chatCompletions)
        #expect(saved.wireProbe?.messages == .available)
        #expect(saved.wireProbe?.responses == .absent)
        #expect(saved.wireProbe?.chatCompletions == .available)
        #expect(
            await coordinator.responsesCapabilities.verdicts()[saved.id] == false
        )

        // Exactly three probe POSTs, one per route — a count check, not just
        // a set, so a regression that duplicates probes cannot pass.
        let probeURLs = await transport.probeURLs
        #expect(probeURLs.count == 3)
        #expect(
            Set(probeURLs)
                == Set([
                    "https://example.com/api/v1/messages",
                    "https://example.com/api/v1/responses",
                    "https://example.com/api/v1/chat/completions",
                ])
        )

        // An unchanged endpoint and credential reuse the previous probe: the
        // rename fires zero new upstream requests.
        _ = try await coordinator.saveProvider(
            ProviderInput(
                id: saved.id,
                name: "renamed",
                baseURL: "https://example.com/api",
                authMode: .bearer,
                responsesWireOverride: .chatCompletions
            )
        )
        #expect(await transport.probeURLs.count == 3)
        let renamed = try #require(store.configuration.providers.first)
        #expect(renamed.wireProbe == saved.wireProbe)

        await coordinator.stopGateway()
    }

    @Test("Persisted probes rehydrate the ledger at launch")
    @MainActor
    func persistedProbesRehydrateAtLaunch() async throws {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Chat Only",
            baseURL: "https://example.com/api",
            authMode: .bearer,
            models: [DiscoveredModel(id: "chat-model")],
            wireProbe: ProviderWireProbe(
                messages: .available,
                responses: .absent,
                chatCompletions: .available
            )
        )
        let coordinator = ApplicationCoordinator(
            configurationStore: ScriptedConfigurationStore(
                configuration: AppConfiguration(providers: [provider])
            ),
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            responsesCapabilities: ResponsesCapabilityLedger()
        )

        _ = try await coordinator.start()

        // The persisted absent route seeds the ledger, so the first Codex
        // request after a relaunch skips the discovery 404.
        #expect(
            await coordinator.responsesWireVerdicts()[providerID] == false
        )
        await coordinator.stopGateway()
    }

    @Test("A save cancelled inside the probe window persists nothing")
    @MainActor
    func cancelledSaveDuringProbePersistsNothing() async throws {
        let transport = ProbeSuspendingCatalogTransport()
        let store = ScriptedConfigurationStore(configuration: AppConfiguration())
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: transport,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            responsesCapabilities: ResponsesCapabilityLedger()
        )
        _ = try await coordinator.startGateway(
            snapshot: RoutingSnapshot(generation: 1, providers: [], mappings: [:])
        )

        let save = Task {
            try await coordinator.saveProvider(
                ProviderInput(
                    name: "Slow Probe",
                    baseURL: "https://example.com/api",
                    authMode: .bearer,
                    credential: "secret"
                )
            )
        }
        await transport.waitUntilProbeWasCalled()
        save.cancel()
        _ = try? await save.value

        #expect(store.saves.isEmpty)
        #expect(store.configuration.providers.isEmpty)
        await coordinator.stopGateway()
    }
}

/// GETs answer the discovery catalog immediately; probe POSTs suspend until
/// their task is cancelled — a host that accepts TCP and never answers.
private actor ProbeSuspendingCatalogTransport: UpstreamTransport {
    private var probeCount = 0
    private var probeWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilProbeWasCalled() async {
        guard probeCount == 0 else {
            return
        }
        await withCheckedContinuation { continuation in
            probeWaiters.append(continuation)
        }
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        guard request.method == .POST else {
            return HTTPClientResponse(
                status: .ok,
                headers: ["content-type": "application/json"],
                body: .bytes(ByteBuffer(string: #"{"data":[{"id":"chat-model"}]}"#))
            )
        }
        probeCount += 1
        let waiters = probeWaiters
        probeWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
        do {
            while true {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        } catch {
            throw CancellationError()
        }
    }
}

/// Serves the discovery catalog on GET and classifies each probe POST by
/// route: messages exist, responses does not, chat completions exists.
private actor WireProbingCatalogTransport: UpstreamTransport {
    private(set) var probeURLs: [String] = []

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        guard request.method == .POST else {
            return HTTPClientResponse(
                status: .ok,
                headers: ["content-type": "application/json"],
                body: .bytes(
                    ByteBuffer(string: #"{"data":[{"id":"chat-model"}]}"#)
                )
            )
        }
        probeURLs.append(request.url)
        let path = URL(string: request.url)?.path ?? ""
        let status: Int
        if path.contains("/v1/messages") {
            status = 422
        } else if path.contains("/v1/responses") {
            status = 404
        } else {
            status = 200
        }
        return HTTPClientResponse(
            status: HTTPResponseStatus(statusCode: status),
            headers: ["content-type": "application/json"],
            body: .bytes(ByteBuffer(string: #"{"detail":"Not Found"}"#))
        )
    }
}
