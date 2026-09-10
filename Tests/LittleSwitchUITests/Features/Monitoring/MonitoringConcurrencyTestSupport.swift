import Foundation

@testable import LittleSwitchCore
@testable import LittleSwitchUI

@MainActor
final class MonitoringConcurrencyFixture {
    let events: SharedEventLog
    let persistence: MonitoringConcurrencyConfigurationStore
    let secrets: MonitoringConcurrencySecrets
    let transport: MonitoringConcurrencyTransport
    let exporter: MonitoringExportService
    let coordinator: ApplicationCoordinator
    private var joins: [@Sendable () async -> Void] = []

    init(
        configuration: MonitoringConfiguration = .init(),
        suspendSend: Bool = false,
        suspendShutdown: Bool = false
    ) {
        let events = SharedEventLog()
        self.events = events
        let persistence = MonitoringConcurrencyConfigurationStore(
            configuration: .init(monitoring: configuration), events: events)
        self.persistence = persistence
        let secrets = MonitoringConcurrencySecrets(events: events)
        self.secrets = secrets
        let transport = MonitoringConcurrencyTransport(
            events: events, suspendSend: suspendSend, suspendShutdown: suspendShutdown)
        self.transport = transport
        let factory: @Sendable (MonitoringSignal) -> any OTLPTransporting = { _ in transport }
        let exporter = MonitoringExportService(store: .init(), transportFactory: factory)
        self.exporter = exporter
        coordinator = ApplicationCoordinator(
            configurationStore: persistence,
            secretStore: secrets,
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: TestGatewayTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            monitoringExporter: exporter
        )
    }

    static var enabledLogs: MonitoringConfiguration {
        .init(logs: .init(enabled: true, endpoint: "https://receiver.example/v1/logs"))
    }

    func withCleanup(_ operation: @MainActor () async throws -> Void) async throws {
        let result: Result<Void, any Error>
        do {
            try await operation()
            result = .success(())
        } catch {
            result = .failure(error)
        }
        await transport.releaseAll()
        for join in joins { await join() }
        joins.removeAll()
        await coordinator.shutdown()
        try result.get()
    }

    func own<Value: Sendable, Failure: Error>(_ task: Task<Value, Failure>) -> Task<Value, Failure> {
        joins.append { _ = await task.result }
        return task
    }

    func beforeRelease<Value: Sendable>(
        description: String, operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let completed = AsyncTestGate()
        let task = Task {
            do {
                let result = try await operation()
                await completed.open()
                return result
            } catch {
                await completed.open()
                throw error
            }
        }
        do {
            try await completed.wait(description: description)
        } catch {
            await transport.releaseAll()
            task.cancel()
            _ = await task.result
            throw error
        }
        return try await task.value
    }
}

struct MonitoringConcurrencyConfigurationStore: ConfigurationStoring {
    private let storage: RecordingConfigurationStore
    private let events: SharedEventLog

    init(configuration: AppConfiguration, events: SharedEventLog) {
        storage = RecordingConfigurationStore(configuration: configuration)
        self.events = events
    }

    var configuration: AppConfiguration { storage.configuration }
    var saves: [AppConfiguration] { storage.saves }

    func load() throws -> AppConfiguration { try storage.load() }

    func save(_ configuration: AppConfiguration) throws {
        try storage.save(configuration)
        let accounts = [configuration.monitoring.metrics.credentialID, configuration.monitoring.logs.credentialID]
        for identifier in accounts.compactMap(\.self) { events.append("save:\(identifier.uuidString)") }
    }
}

struct MonitoringConcurrencySecrets: SecretStore {
    let storage = MemorySecretStore()
    let events: SharedEventLog

    func read(account: SecretAccount) throws -> String? {
        if case .monitoring(let id) = account { events.append("read:\(id.uuidString)") }
        return try storage.read(account: account)
    }

    func write(_ secret: String, account: SecretAccount) throws {
        if case .monitoring(let id) = account { events.append("write:\(id.uuidString)") }
        try storage.write(secret, account: account)
    }

    func delete(account: SecretAccount) throws {
        if case .monitoring(let id) = account { events.append("delete:\(id.uuidString)") }
        try storage.delete(account: account)
    }
}

actor MonitoringConcurrencyTransport: OTLPTransporting {
    let sendStarted = AsyncTestGate()
    let shutdownStarted = AsyncTestGate()
    private let sendRelease = AsyncTestGate()
    private let shutdownRelease = AsyncTestGate()
    private let events: SharedEventLog
    private let suspendSend: Bool
    private let suspendShutdown: Bool
    private(set) var sendCount = 0
    private(set) var shutdownCount = 0

    init(events: SharedEventLog, suspendSend: Bool, suspendShutdown: Bool) {
        self.events = events
        self.suspendSend = suspendSend
        self.suspendShutdown = suspendShutdown
    }

    func send(to endpoint: URL, body: Data, bearer: String?) async throws -> OTLPHTTPResponse {
        sendCount += 1
        events.append("send-started")
        await sendStarted.open()
        if suspendSend { try await sendRelease.wait() }
        events.append("send-finished")
        return .init(status: 200, contentType: "application/json", retryAfter: nil, body: Data("{}".utf8))
    }

    func shutdown() async {
        shutdownCount += 1
        events.append("shutdown-started")
        await shutdownStarted.open()
        if suspendShutdown { try? await shutdownRelease.wait() }
        events.append("shutdown-finished")
    }

    func releaseAll() async {
        await sendRelease.open()
        await shutdownRelease.open()
    }
}
