import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

@testable import LittleSwitchUI

@MainActor
struct ProviderEdgeCoverageFixture {
    let providerID: UUID
    let provider: Provider
    let configuration: AppConfiguration
    let store: ScriptedConfigurationStore
    let secrets: ScriptedSecretStore
    let state: GatewayState
    let coordinator: ApplicationCoordinator

    static func make(
        credential: String? = nil,
        requestPool: (any ProviderRequestPooling)? = nil,
        discoveryTransport: any UpstreamTransport = StaticCatalogTransport()
    ) async throws -> Self {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: credential == nil ? .none : .bearer,
            models: [DiscoveredModel(id: "applied")],
            status: .ready
        )
        let configuration = AppConfiguration(
            providers: [provider],
            mappings: [
                "claude-sonnet-5": ModelMapping(
                    providerID: providerID,
                    modelID: "applied"
                )
            ]
        )
        let snapshot = RoutingSnapshot(
            generation: 0,
            providers: configuration.providers,
            mappings: configuration.mappings
        )
        let state: GatewayState
        if let requestPool {
            state = GatewayState(snapshot: snapshot, requestPool: requestPool)
        } else {
            state = GatewayState(snapshot: snapshot)
        }
        let store = ScriptedConfigurationStore(configuration: configuration)
        let secrets = ScriptedSecretStore(
            values: credential.map { [.provider(providerID): $0] } ?? [:]
        )
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: secrets,
            profileManager: ScriptedClaudeProfileManager(),
            claudeController: ScriptedApplicationController(),
            discoveryTransport: discoveryTransport,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            gatewayStateOverride: state
        )
        await coordinator.installConfigurationForEdgeCoverage(configuration)
        try await coordinator.startGateway(snapshot: snapshot)
        return Self(
            providerID: providerID,
            provider: provider,
            configuration: configuration,
            store: store,
            secrets: secrets,
            state: state,
            coordinator: coordinator
        )
    }
}

extension ApplicationCoordinator {
    func installConfigurationForEdgeCoverage(_ configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func currentProviderIntentForEdgeCoverage(providerID: UUID) -> UInt64? {
        providerIntents[providerID]
    }

    func supersedeProviderIntentForEdgeCoverage(providerID: UUID) {
        providerIntentGeneration &+= 1
        providerIntents[providerID] = providerIntentGeneration
    }

    func removeProviderForEdgeCoverage(providerID: UUID) {
        configuration.providers.removeAll { $0.id == providerID }
    }
}

actor OneShotSuspendedReconfigurationPool: ProviderRequestPooling {
    private let reconfigureEntered = AsyncTestGate()
    private let reconfigureReleased = AsyncTestGate()
    private var shouldSuspendNextReconfiguration = false

    func suspendNextReconfiguration() {
        shouldSuspendNextReconfiguration = true
    }

    func admit(_ admission: ProviderRequestAdmission) async throws {
        _ = admission
    }

    func finish(eventID: UUID) async {
        _ = eventID
    }

    func shutdown() async {}

    func reconfigure(_ configuration: ProviderRequestPoolConfiguration) async {
        _ = configuration
        guard shouldSuspendNextReconfiguration else {
            return
        }
        shouldSuspendNextReconfiguration = false
        await reconfigureEntered.open()
        try? await reconfigureReleased.wait()
    }

    func snapshot() async -> ProviderRequestPoolSnapshot {
        ProviderRequestPoolSnapshot(
            totalRunning: 0,
            totalWaiting: 0,
            providers: []
        )
    }

    func waitUntilReconfigurationWasCalled() async throws {
        try await reconfigureEntered.wait(
            description: "suspended provider pool reconfiguration"
        )
    }

    func releaseReconfiguration() async {
        await reconfigureReleased.open()
    }
}

actor GatedProviderCatalogTransport: UpstreamTransport {
    private let requestEntered = AsyncTestGate()
    private let requestReleased = AsyncTestGate()
    private var shouldSuspendNextRequest = false
    private(set) var executeCount = 0

    func suspendNextRequest() {
        shouldSuspendNextRequest = true
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        executeCount += 1
        if shouldSuspendNextRequest {
            shouldSuspendNextRequest = false
            await requestEntered.open()
            try await requestReleased.wait()
        }
        let isVersionRequest = request.url.hasSuffix("/api/version")
        return HTTPClientResponse(
            status: isVersionRequest ? .notFound : .ok,
            headers: ["content-type": "application/json"],
            body: .bytes(
                ByteBuffer(
                    string: isVersionRequest
                        ? #"{"error":"not ollama"}"#
                        : #"{"data":[{"id":"applied"}]}"#
                )
            )
        )
    }

    func shutdown() async throws {}

    func waitUntilRequestWasCalled() async throws {
        try await requestEntered.wait(
            description: "suspended provider catalog request"
        )
    }

    func releaseRequest() async {
        await requestReleased.open()
    }
}

final class BlockingSecretReadStore: SecretStore, @unchecked Sendable {
    private let readEntered = DispatchSemaphore(value: 0)
    private let readReleased = DispatchSemaphore(value: 0)

    func read(account: SecretAccount) throws -> String? {
        _ = account
        readEntered.signal()
        guard readReleased.wait(timeout: .now() + 30) == .success else {
            throw AsyncTestTimeout(operation: "release of the blocked credential read")
        }
        return nil
    }

    func write(_ secret: String, account: SecretAccount) throws {
        _ = secret
        _ = account
    }

    func delete(account: SecretAccount) throws {
        _ = account
    }

    func waitUntilReadIsBlocked() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    returning: self.readEntered.wait(timeout: .now() + 5) == .success
                )
            }
        }
    }

    func releaseRead() {
        readReleased.signal()
    }
}

final class BlockingCoordinatorActorGate: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    func block() throws {
        entered.signal()
        guard released.wait(timeout: .now() + 30) == .success else {
            throw AsyncTestTimeout(operation: "release of the blocked coordinator")
        }
    }

    func waitUntilBlocked() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    returning: self.entered.wait(timeout: .now() + 5) == .success
                )
            }
        }
    }

    func release() {
        released.signal()
    }
}

extension ApplicationCoordinator {
    func blockActorForEdgeCoverage(_ gate: BlockingCoordinatorActorGate) throws {
        try gate.block()
    }
}

func waitUntilRoutingMutationIsActiveForEdgeCoverage(
    routingMutationGuard: GatewayRoutingMutationGuard,
    providerID: UUID,
    secretStore: any SecretStore
) async throws {
    _ = try await eventually(
        description: "active provider routing mutation token"
    ) {
        do {
            _ = try await routingMutationGuard.readCredential(
                providerID: providerID,
                secretStore: secretStore
            )
            return nil as Bool?
        } catch GatewayAdmissionError.invalidated {
            return true
        }
    }
}
