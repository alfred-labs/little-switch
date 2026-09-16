import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator provider routing security")
struct ProviderRoutingSecurityTests {
    @Test("Credential replacement is atomic with gateway routing replacement")
    @available(macOS 15.0, *)
    func credentialReplacementIsAtomicWithRouting() async throws {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .bearer,
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
        let store = BlockingConfigurationStore(configuration: configuration)
        let secrets = ScriptedSecretStore(values: [.provider(providerID): "old-secret"])
        let state = GatewayState(
            snapshot: RoutingSnapshot(
                generation: 0,
                providers: configuration.providers,
                mappings: configuration.mappings
            )
        )
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: secrets,
            profileManager: ScriptedClaudeProfileManager(),
            claudeController: ScriptedApplicationController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            gatewayStateOverride: state
        )
        _ = try await coordinator.start()
        let oldCapture = await state.routingCapture()
        store.blockNextSave()

        let save = Task(executorPreference: BlockingTestExecutor()) {
            try await coordinator.saveProvider(
                ProviderInput(
                    id: providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11435",
                    authMode: .bearer,
                    credential: "new-secret"
                )
            )
        }
        defer {
            store.releaseSave()
            save.cancel()
        }

        try #require(await store.waitUntilSaveIsBlocked())
        #expect(secrets.value(for: .provider(providerID)) == "new-secret")
        await #expect(throws: GatewayAdmissionError.invalidated) {
            _ = try await state.providerCredential(
                providerID: providerID,
                capture: oldCapture,
                secretStore: secrets
            )
        }

        store.releaseSave()
        _ = try await save.value

        let newCapture = await state.routingCapture()
        let credential = try await state.providerCredential(
            providerID: providerID,
            capture: newCapture,
            secretStore: secrets
        )
        #expect(credential == "new-secret")
        await #expect(throws: GatewayAdmissionError.invalidated) {
            _ = try await state.providerCredential(
                providerID: providerID,
                capture: oldCapture,
                secretStore: secrets
            )
        }
        await coordinator.shutdown(mode: .handoff)
    }

    @Test("Deleting a provider supersedes its suspended refresh without corrupting peers")
    func deleteSupersedesSuspendedRefresh() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let first = Provider(
            id: firstID,
            name: "First",
            baseURL: "http://127.0.0.1:11434",
            authMode: .bearer,
            models: [DiscoveredModel(id: "applied")],
            status: .ready
        )
        let second = Provider(
            id: secondID,
            name: "Second",
            baseURL: "http://127.0.0.1:11435",
            authMode: .none,
            models: [DiscoveredModel(id: "applied")],
            status: .ready
        )
        let configuration = AppConfiguration(
            providers: [first, second],
            mappings: [
                "claude-sonnet-5": ModelMapping(
                    providerID: firstID,
                    modelID: "applied"
                )
            ]
        )
        let store = ScriptedConfigurationStore(configuration: configuration)
        let secrets = ScriptedSecretStore(values: [.provider(firstID): "secret"])
        let transport = GatedCatalogTransport()
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: secrets,
            profileManager: ScriptedClaudeProfileManager(),
            claudeController: ScriptedApplicationController(),
            discoveryTransport: transport,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
        _ = try await coordinator.start()
        await transport.blockNextRequest()

        let refresh = Task {
            try await coordinator.refreshProvider(id: firstID)
        }
        await transport.waitUntilRequestIsBlocked()
        let deleted = try await coordinator.deleteProvider(id: firstID)
        #expect(deleted.configuration.providers.map(\.id) == [secondID])

        await transport.releaseRequest()
        await #expect(throws: ApplicationCoordinator.Error.providerMutationSuperseded) {
            _ = try await refresh.value
        }

        let final = await coordinator.snapshot().configuration
        #expect(final.providers.map(\.id) == [secondID])
        #expect(final.mappings.isEmpty)
        #expect(secrets.value(for: .provider(firstID)) == nil)
        await coordinator.shutdown(mode: .handoff)
    }

    @Test("A failed credential rollback stays closed until a successful provider save")
    func failedCredentialRollbackIsRecoverable() async throws {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .bearer,
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
        let store = ScriptedConfigurationStore(configuration: configuration)
        let secrets = ScriptedSecretStore(values: [.provider(providerID): "old-secret"])
        let state = GatewayState(
            snapshot: RoutingSnapshot(
                generation: 0,
                providers: configuration.providers,
                mappings: configuration.mappings
            )
        )
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: secrets,
            profileManager: ScriptedClaudeProfileManager(),
            claudeController: ScriptedApplicationController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            gatewayStateOverride: state
        )
        _ = try await coordinator.start()
        let captureBeforeFailure = await state.routingCapture()
        store.failFutureSaves(at: [1])
        secrets.failWrites(on: [2])

        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await coordinator.saveProvider(
                ProviderInput(
                    id: providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11435",
                    authMode: .bearer,
                    credential: "uncertain-secret"
                )
            )
        }
        await #expect(throws: GatewayAdmissionError.invalidated) {
            _ = try await state.providerCredential(
                providerID: providerID,
                capture: captureBeforeFailure,
                secretStore: secrets
            )
        }

        secrets.failWrites(on: [])
        _ = try await coordinator.saveProvider(
            ProviderInput(
                id: providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11435",
                authMode: .bearer,
                credential: "recovered-secret"
            )
        )

        let recoveredCapture = await state.routingCapture()
        #expect(
            try await state.providerCredential(
                providerID: providerID,
                capture: recoveredCapture,
                secretStore: secrets
            ) == "recovered-secret"
        )
        await #expect(throws: GatewayAdmissionError.invalidated) {
            _ = try await state.providerCredential(
                providerID: providerID,
                capture: captureBeforeFailure,
                secretStore: secrets
            )
        }
        await coordinator.shutdown(mode: .handoff)
    }
}

private actor GatedCatalogTransport: UpstreamTransport {
    private var shouldBlockNextRequest = false
    private var requestIsBlocked = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func blockNextRequest() {
        shouldBlockNextRequest = true
        requestIsBlocked = false
    }

    func waitUntilRequestIsBlocked() async {
        if requestIsBlocked {
            return
        }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    func releaseRequest() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func execute(
        _ request: AsyncHTTPClient.HTTPClientRequest
    ) async throws -> AsyncHTTPClient.HTTPClientResponse {
        // Image and wire probes must not consume the catalog-refresh gate.
        guard request.method == .GET else {
            return AsyncHTTPClient.HTTPClientResponse(status: .forbidden)
        }
        if shouldBlockNextRequest {
            shouldBlockNextRequest = false
            requestIsBlocked = true
            let waiters = enteredWaiters
            enteredWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        return AsyncHTTPClient.HTTPClientResponse(
            status: .ok,
            headers: ["content-type": "application/json"],
            body: .bytes(NIOCore.ByteBuffer(string: #"{"data":[{"id":"applied"}]}"#))
        )
    }

    func shutdown() async throws {}
}

private final class BlockingConfigurationStore: ConfigurationStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let saveEntered = DispatchSemaphore(value: 0)
    private let saveReleased = DispatchSemaphore(value: 0)
    private var configuration: AppConfiguration
    private var shouldBlockNextSave = false

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func load() throws -> AppConfiguration {
        lock.withLock { configuration }
    }

    func save(_ configuration: AppConfiguration) throws {
        let shouldBlock = lock.withLock {
            self.configuration = configuration
            let shouldBlock = shouldBlockNextSave
            shouldBlockNextSave = false
            return shouldBlock
        }
        guard shouldBlock else {
            return
        }
        saveEntered.signal()
        guard saveReleased.wait(timeout: .now() + 30) == .success else {
            throw AsyncTestTimeout(operation: "release of the blocked configuration save")
        }
    }

    func blockNextSave() {
        lock.withLock { shouldBlockNextSave = true }
    }

    func waitUntilSaveIsBlocked() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    returning: self.saveEntered.wait(timeout: .now() + 5) == .success
                )
            }
        }
    }

    func releaseSave() {
        saveReleased.signal()
    }
}
