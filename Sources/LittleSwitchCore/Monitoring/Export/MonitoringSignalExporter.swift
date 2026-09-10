import Foundation

/// One owner per signal. Neither the driver nor an in-flight request is detached.
package actor MonitoringSignalExporter {
    let signal: MonitoringSignal
    let store: MonitoringStore
    let clock: any MonitoringExportClock
    let transportFactory: @Sendable (MonitoringSignal) -> any OTLPTransporting
    let jitter: @Sendable () -> Double
    let logLimits: MonitoringLogExportLimits
    let encodeMetrics: @Sendable (MonitoringMetricsSnapshot) throws -> OTLPEncodingResult
    var providerPool: GatewayState?
    var destination = MonitoringDestination()
    var bearer: String?
    var endpoint: URL?
    var transport: (any OTLPTransporting)?
    var generation: UInt64 = 0
    var driverTask: Task<Void, Never>?
    var waitTask: Task<Void, Never>?
    var sendTask: Task<Void, Never>?
    var state = MonitoringSignalExportStatus()
    var logs: MonitoringLogExportQueue
    var pendingMetrics: [OTLPPayload] = []
    var activeMetrics: [OTLPPayload] = []
    var metricVersion: UInt64 = 0
    var activeMetricVersion: UInt64 = 0
    var nextSample = Duration.zero
    var interval = 15
    var minimumLevel = MonitoringLevel.info
    var retrySchedule: MonitoringExportRetrySchedule?
    var retryAttempt = 0
    var forceFlush = false
    var forceSample = false
    var finishing = false
    var flushContinuation: CheckedContinuation<Void, Never>?
    var testContinuation: CheckedContinuation<MonitoringExportTestOutcome, Never>?
    var completedTest: MonitoringExportTestOutcome?
    var testEventID: UUID?
    var testMetricVersion: UInt64?

    init(
        signal: MonitoringSignal,
        store: MonitoringStore,
        transportFactory: @escaping @Sendable (MonitoringSignal) -> any OTLPTransporting,
        clock: any MonitoringExportClock,
        jitter: @escaping @Sendable () -> Double,
        logLimits: MonitoringLogExportLimits,
        encodeMetrics: @escaping @Sendable (MonitoringMetricsSnapshot) throws -> OTLPEncodingResult
    ) {
        self.signal = signal
        self.store = store
        self.transportFactory = transportFactory
        self.clock = clock
        self.jitter = jitter
        self.logLimits = logLimits
        self.encodeMetrics = encodeMetrics
        logs = MonitoringLogExportQueue(resource: store.resource, limits: logLimits)
    }

    func configure(_ configuration: MonitoringConfiguration, bearer suppliedBearer: String?) async {
        let incoming = signal == .metrics ? configuration.metrics : configuration.logs
        let token = incoming.authentication == .bearer ? suppliedBearer : nil
        let issue = configurationIssue(incoming, bearer: token, interval: configuration.metricIntervalSeconds)
        if incoming == destination, token == bearer, transport != nil, issue == nil {
            if interval != configuration.metricIntervalSeconds {
                interval = configuration.metricIntervalSeconds
                nextSample = await clock.now().monotonic + .seconds(interval)
            }
            minimumLevel = configuration.minimumLogLevel
            logs.filter(minimumLevel: minimumLevel, includingBatch: sendTask == nil)
            checkTestRetention()
            wake()
            return
        }
        await stop(reason: .reconfigured)
        destination = incoming
        bearer = token
        interval = configuration.metricIntervalSeconds
        minimumLevel = configuration.minimumLogLevel
        guard incoming.enabled else { return }
        if let issue {
            state.state = .failed
            state.configurationIssue = issue
            return
        }
        endpoint = try? MonitoringEndpoint.validate(incoming.endpoint)
        transport = transportFactory(signal)
        finishing = false
        state.state = .idle
        state.configurationIssue = nil
        nextSample = await clock.now().monotonic + .seconds(interval)
        let current = generation
        driverTask = Task { await self.run(generation: current) }
    }

    func updateProviderPool(_ providerPool: GatewayState?) { self.providerPool = providerPool }

    func enqueue(_ entry: MonitoringLogEntry) async {
        let current = generation
        let now = await clock.now()
        guard current == generation, transport != nil, !finishing, entry.level >= minimumLevel else { return }
        let drops = logs.append(entry, at: now.monotonic, preservingBatch: sendTask != nil)
        checkTestRetention()
        wake()
        await record(drops)
    }

    func snapshot() -> MonitoringSignalExportStatus {
        var snapshot = state
        if signal == .logs {
            snapshot.queuedCount = logs.retainedCount
            snapshot.queuedBytes = logs.retainedBytes
        } else {
            snapshot.queuedCount = (activeMetrics + pendingMetrics).reduce(0) { $0 + $1.itemCount }
            snapshot.queuedBytes = (activeMetrics + pendingMetrics).reduce(0) { $0 + $1.body.count }
        }
        return snapshot
    }

    func test(_ entry: MonitoringLogEntry) async -> MonitoringExportTestOutcome {
        let current = generation
        if let issue = state.configurationIssue { return .invalidConfiguration(issue) }
        guard transport != nil, !finishing else { return .disabled }
        let now = await clock.now()
        guard current == generation, transport != nil, !finishing, !Task.isCancelled else { return .cancelled }
        completedTest = nil
        testEventID = signal == .logs ? entry.eventID : nil
        testMetricVersion = signal == .metrics ? metricVersion + 1 : nil
        forceSample = signal == .metrics
        forceFlush = true
        // Reserving the marker and appending it are synchronous actor operations.
        // The bounded result slot retains an acknowledgement that beats the waiter.
        let drops = signal == .logs ? logs.append(entry, at: now.monotonic, preservingBatch: sendTask != nil) : [:]
        checkTestRetention()
        wake()
        await record(drops)
        guard current == generation else { return .cancelled }
        if retrySchedule != nil, let failure = state.failure { finishTest(.retrying(failure)) }
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let completedTest {
                    continuation.resume(returning: completedTest)
                } else {
                    testContinuation = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelTest(generation: current) }
        }
        if current == generation { completedTest = nil }
        return result
    }

    func flush() async {
        guard transport != nil else { return }
        finishing = true
        forceSample = signal == .metrics
        forceFlush = true
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                flushContinuation = continuation
                wake()
            }
        } onCancel: {
            Task { await self.finishFlush() }
        }
    }

    func stop(reason: MonitoringDropReason) async {
        generation &+= 1
        let driver = driverTask
        let send = sendTask
        let previousTransport = transport
        driverTask = nil
        sendTask = nil
        transport = nil
        endpoint = nil
        bearer = nil
        driver?.cancel()
        send?.cancel()
        waitTask?.cancel()
        waitTask = nil
        let count = signal == .logs ? logs.discardAll() : UInt64(snapshot().queuedCount)
        pendingMetrics.removeAll(keepingCapacity: false)
        activeMetrics.removeAll(keepingCapacity: false)
        state.state = .disabled
        state.lastAccepted = nil
        state.nextRetry = nil
        state.failure = nil
        state.configurationIssue = nil
        state.warning = send == nil ? nil : .deliveryUncertain
        retrySchedule = nil
        retryAttempt = 0
        forceFlush = false
        forceSample = false
        finishTest(.cancelled)
        finishFlush()
        await record([reason: count])
        await driver?.value
        await send?.value
        await previousTransport?.shutdown()
    }

    func wake() { waitTask?.cancel() }

    func finishTest(_ result: MonitoringExportTestOutcome) {
        completedTest = result
        testContinuation?.resume(returning: result)
        testContinuation = nil
        testEventID = nil
        testMetricVersion = nil
    }

    private func cancelTest(generation current: UInt64) {
        if current == generation { finishTest(.cancelled) }
    }

    func finishFlush() {
        flushContinuation?.resume()
        flushContinuation = nil
    }

    func checkTestRetention() {
        if let testEventID, !logs.contains(testEventID) { finishTest(.cancelled) }
    }

    func record(_ drops: [MonitoringDropReason: UInt64]) async {
        for (reason, count) in drops where count > 0 {
            state.drops[reason] = monitoringSum(state.drops[reason, default: 0], count)
        }
        for (reason, count) in drops where count > 0 {
            await store.recordDrop(signal: signal, reason: reason, count: count)
        }
    }

    private func configurationIssue(
        _ destination: MonitoringDestination, bearer: String?, interval: Int
    ) -> MonitoringExportConfigurationIssue? {
        if signal == .metrics, !MonitoringConfiguration.metricIntervalSecondsRange.contains(interval) {
            return .invalidInterval
        }
        if (try? MonitoringEndpoint.validate(destination.endpoint)) == nil { return .invalidEndpoint }
        if destination.authentication == .bearer {
            guard destination.credentialID != nil, let bearer, !bearer.isEmpty,
                bearer.utf8.allSatisfy({ (33...126).contains($0) })
            else { return .missingCredential }
        }
        return nil
    }
}
