import Foundation
import LittleSwitchCommon

public actor MonitoringExportService {
    public private(set) var configuration = MonitoringConfiguration()
    nonisolated public let store: MonitoringStore
    private let metrics: MonitoringSignalExporter
    private let logs: MonitoringSignalExporter
    private var configurationTask: Task<Void, Never>?
    private var testingTask: Task<MonitoringExportTestResult, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var shuttingDown = false

    public init(store: MonitoringStore) {
        self.init(
            store: store, transportFactory: { _ in OTLPHTTPTransport() }, clock: MonitoringContinuousExportClock())
    }

    package init(
        store: MonitoringStore,
        transportFactory: @escaping @Sendable (MonitoringSignal) -> any OTLPTransporting,
        clock: any MonitoringExportClock = MonitoringContinuousExportClock(),
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0.5...1.5) },
        logLimits: MonitoringLogExportLimits = .init(),
        encodeMetrics: @escaping @Sendable (MonitoringMetricsSnapshot) throws -> OTLPEncodingResult = {
            try OTLPMetricsEncoder.batches($0)
        }
    ) {
        self.store = store
        metrics = MonitoringSignalExporter(
            signal: .metrics,
            store: store,
            transportFactory: transportFactory,
            clock: clock,
            jitter: jitter,
            logLimits: logLimits,
            encodeMetrics: encodeMetrics)
        logs = MonitoringSignalExporter(
            signal: .logs,
            store: store,
            transportFactory: transportFactory,
            clock: clock,
            jitter: jitter,
            logLimits: logLimits,
            encodeMetrics: encodeMetrics)
    }

    public func configure(
        _ configuration: MonitoringConfiguration, metricsBearer: String? = nil, logsBearer: String? = nil
    ) async {
        guard !shuttingDown else { return }
        self.configuration = configuration
        let previous = configurationTask
        let task = Task {
            await previous?.value
            async let metricsChange: Void = metrics.configure(configuration, bearer: metricsBearer)
            async let logsChange: Void = logs.configure(configuration, bearer: logsBearer)
            _ = await (metricsChange, logsChange)
        }
        configurationTask = task
        await task.value
    }

    public func updateProviderPool(_ state: GatewayState?) async { await metrics.updateProviderPool(state) }
    public func enqueue(_ entry: MonitoringLogEntry) async { await logs.enqueue(entry) }

    public func status() async -> MonitoringExportStatus {
        async let metricsStatus = metrics.snapshot()
        async let logsStatus = logs.snapshot()
        return await .init(metrics: metricsStatus, logs: logsStatus, isTesting: testingTask != nil)
    }

    public func testExport() async -> MonitoringExportTestResult {
        guard !shuttingDown else { return .init(metrics: .cancelled, logs: .cancelled) }
        await configurationTask?.value
        guard !shuttingDown else { return .init(metrics: .cancelled, logs: .cancelled) }
        if let testingTask { return await testingTask.value }
        guard configuration.metrics.enabled || configuration.logs.enabled else { return .init() }
        let task = Task {
            let entry = await store.markTest()
            async let metricsResult = metrics.test(entry)
            async let logsResult = logs.test(entry)
            return await MonitoringExportTestResult(metrics: metricsResult, logs: logsResult)
        }
        testingTask = task
        let result = await task.value
        testingTask = nil
        return result
    }

    public func shutdown(flushTimeout: Duration = .seconds(2)) async {
        if let shutdownTask {
            await shutdownTask.value
            return
        }
        shuttingDown = true
        let task = Task { await self.finishShutdown(flushTimeout: flushTimeout) }
        shutdownTask = task
        await task.value
    }

    private func finishShutdown(flushTimeout: Duration) async {
        await configurationTask?.value
        testingTask?.cancel()
        _ = await testingTask?.value
        testingTask = nil
        if flushTimeout > .zero {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    async let metricsFlush: Void = self.metrics.flush()
                    async let logsFlush: Void = self.logs.flush()
                    _ = await (metricsFlush, logsFlush)
                }
                group.addTask { try? await Task.sleep(for: flushTimeout) }
                await group.next()
                group.cancelAll()
            }
        }
        async let metricsStop: Void = metrics.stop(reason: .transportFailure)
        async let logsStop: Void = logs.stop(reason: .transportFailure)
        _ = await (metricsStop, logsStop)
    }
}
