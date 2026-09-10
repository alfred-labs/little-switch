import Foundation

extension MonitoringSignalExporter {
    func run(generation current: UInt64) async {
        while current == generation, !Task.isCancelled {
            let now = await clock.now()
            guard current == generation, !Task.isCancelled else { return }
            await prepare(now: now, generation: current)
            guard current == generation, !Task.isCancelled else { return }
            startDelivery(now: now, generation: current)
            if finishing, !forceSample, sendTask == nil, snapshot().queuedCount == 0 { finishFlush() }
            let deadline = nextDeadline(now: now.monotonic)
            let sleeper = Task<Void, Never> { [clock] in try? await clock.sleep(until: deadline) }
            waitTask = sleeper
            await withTaskCancellationHandler {
                await sleeper.value
            } onCancel: {
                sleeper.cancel()
            }
            if current == generation { waitTask = nil }
        }
    }

    private func prepare(now: MonitoringExportTime, generation current: UInt64) async {
        if signal == .logs {
            let expired = logs.expire(at: now.monotonic, includingBatch: sendTask == nil)
            checkTestRetention()
            await record([.expired: expired])
        } else if forceSample || (!finishing && now.monotonic >= nextSample) {
            forceSample = false
            nextSample = now.monotonic + .seconds(interval)
            let pool = await providerPool?.requestPoolSnapshot()
            let snapshot = await store.snapshot(at: now.date, providerPool: pool)
            guard current == generation, !Task.isCancelled else { return }
            do {
                let encoded = try encodeMetrics(snapshot)
                if sendTask == nil, retrySchedule != nil { activeMetrics.removeAll(keepingCapacity: false) }
                pendingMetrics = encoded.payloads
                metricVersion &+= 1
                await record([.oversize: UInt64(encoded.dropped)])
            } catch {
                state.state = .failed
                state.failure = .invalidResponse
                finishTest(.failed(.invalidResponse))
                await record([.rejected: UInt64(snapshot.families.reduce(0) { $0 + $1.points.count })])
            }
        }
    }

    private func startDelivery(now: MonitoringExportTime, generation current: UInt64) {
        guard sendTask == nil, let transport, let endpoint,
            retrySchedule?.isDue(at: now.monotonic) ?? true
        else { return }
        let payload: OTLPPayload
        let containsTest: Bool
        if signal == .logs {
            let flushDue = logs.oldestWaitingAt.map { now.monotonic >= $0 + .seconds(2) } ?? false
            guard forceFlush || flushDue || logs.waitingCount >= logLimits.maximumBatchEntries || logs.batch != nil,
                let batch = logs.beginBatch()
            else { return }
            payload = .init(body: batch.body, itemCount: batch.entries.count)
            containsTest =
                testEventID.map { identifier in batch.entries.contains { $0.eventID == identifier } } ?? false
        } else {
            if activeMetrics.isEmpty {
                activeMetrics = pendingMetrics
                pendingMetrics.removeAll(keepingCapacity: false)
                activeMetricVersion = metricVersion
            }
            guard let first = activeMetrics.first else { return }
            payload = first
            // The JSON encoder emits this exact closed-schema metric name. A test is
            // acknowledged only by its own fragment, never by an earlier cumulative fragment.
            let marker = Data(#""name":"littleswitch.monitoring.test""#.utf8)
            containsTest =
                testMetricVersion.map {
                    let markerRange = first.body.range(of: marker)
                    return activeMetricVersion >= $0 && markerRange != nil
                } ?? false
        }
        state.state = .sending
        state.nextRetry = nil
        retrySchedule = nil
        let token = bearer
        sendTask = Task {
            let result: OTLPExportResult
            var retryAfter: String?
            do {
                let response = try await transport.send(to: endpoint, body: payload.body, bearer: token)
                result = OTLPExportResponse.parse(response, signal: self.signal)
                retryAfter = response.retryAfter
            } catch {
                result = OTLPExportResponse.classify(error)
            }
            await self.complete(
                result,
                retryAfter: retryAfter,
                count: payload.itemCount,
                containsTest: containsTest,
                generation: current)
        }
    }

    private func nextDeadline(now: Duration) -> Duration {
        var deadline = now + .seconds(300)
        if signal == .metrics, !finishing { deadline = min(deadline, nextSample) }
        if let retryAt = retrySchedule?.deadline, retryAt > now { deadline = min(deadline, retryAt) }
        if signal == .logs {
            let oldest = sendTask == nil ? logs.oldestEnqueuedAt : logs.oldestWaitingAt
            if let oldest { deadline = min(deadline, oldest + logLimits.retention) }
            if sendTask == nil, retrySchedule?.isDue(at: now) ?? true, let first = logs.oldestWaitingAt {
                deadline = min(deadline, first + .seconds(2))
            }
        }
        return max(now + .milliseconds(1), deadline)
    }
}
