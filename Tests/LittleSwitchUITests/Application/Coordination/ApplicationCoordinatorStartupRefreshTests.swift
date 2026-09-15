import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchUI

@MainActor

extension ApplicationCoordinatorTests {
    @Test("Startup refreshes catalogs and concurrent refreshes are coalesced")
    func startupAndCoalescing() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-coordinator-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let providerID = UUID()
        let store = ConfigurationStore(
            fileURL: root.appending(path: "config.json"),
            backupDirectory: root.appending(path: "configuration-backups")
        )
        try store.save(
            AppConfiguration(
                providers: [
                    Provider(
                        id: providerID,
                        name: "Local",
                        baseURL: "http://127.0.0.1:11434",
                        authMode: .none,
                        models: [DiscoveredModel(id: "stale")]
                    )
                ]
            )
        )
        let transport = DelayedCatalogTransport()
        let gateway = TestGatewayServer()
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: ClaudeProfileManager(paths: ClaudeProfilePaths(applicationSupport: root)),
            claudeController: TestClaudeController(),
            discoveryTransport: transport,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: gateway
        )

        let startup = try await coordinator.start()
        #expect(startup.configuration.providers.first?.models == [DiscoveredModel(id: "fresh")])
        #expect(startup.proxyRunning)
        #expect(await transport.discoveryRequestCount == 2)
        #expect(await transport.catalogRequestCount == 1)

        async let first = coordinator.refreshProvider(id: providerID)
        async let second = coordinator.refreshProvider(id: providerID)
        _ = try await (first, second)

        #expect(await transport.discoveryRequestCount == 4)
        #expect(await transport.catalogRequestCount == 2)
        #expect(await transport.requestURLs.filter { $0.hasSuffix("/api/version") }.count == 2)

        let disconnected = try await coordinator.disconnect()
        #expect(disconnected.proxyRunning)
        await coordinator.shutdown()
        #expect(!(await coordinator.snapshot()).proxyRunning)
        #expect(await transport.didShutdown)
    }
}

actor DelayedCatalogTransport: UpstreamTransport {
    private(set) var requestURLs: [String] = []
    private(set) var didShutdown = false

    // Background capability probes are not catalog refresh exchanges.
    var discoveryRequestCount: Int {
        requestURLs.filter { $0.hasSuffix("/api/version") || $0.hasSuffix("/v1/models") }.count
    }
    var catalogRequestCount: Int {
        requestURLs.filter { $0.hasSuffix("/v1/models") }.count
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        requestURLs.append(request.url)
        try await Task.sleep(for: .milliseconds(50))
        if request.url.hasSuffix("/api/version") {
            return HTTPClientResponse(
                status: .notFound,
                headers: ["content-type": "application/json"],
                body: .bytes(ByteBuffer(string: #"{"error":"not ollama"}"#))
            )
        }
        return HTTPClientResponse(
            status: .ok,
            headers: ["content-type": "application/json"],
            body: .bytes(ByteBuffer(string: #"{"data":[{"id":"fresh"}]}"#))
        )
    }

    func shutdown() async throws {
        didShutdown = true
    }
}

@MainActor
struct FailingSaveFixture {
    let root: URL
    let providerID: UUID
    let store: FailNextConfigurationStore
    let appliedConfiguration: AppConfiguration
    let coordinator: ApplicationCoordinator

    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-failing-save-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [
                DiscoveredModel(id: "applied"),
                DiscoveredModel(id: "replacement"),
            ],
            status: .ready
        )
        let initial = AppConfiguration(
            providers: [provider],
            mappings: [
                "claude-opus-5": ModelMapping(
                    providerID: providerID,
                    modelID: "applied"
                )
            ],
            autoMode: true,
            connected: false
        )
        let backing = ConfigurationStore(
            fileURL: root.appending(path: "config.json"),
            backupDirectory: root.appending(path: "configuration-backups")
        )
        try backing.save(initial)
        let store = FailNextConfigurationStore(backing: backing)
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: ClaudeProfileManager(
                paths: ClaudeProfilePaths(applicationSupport: root)
            ),
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
        _ = try await coordinator.start()
        return Self(
            root: root,
            providerID: providerID,
            store: store,
            appliedConfiguration: try store.load(),
            coordinator: coordinator
        )
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}
