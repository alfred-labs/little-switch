import Foundation
import LittleSwitchCommon

extension MonitoringSignalExporter {
    func complete(
        _ result: OTLPExportResult,
        retryAfter: String?,
        count: Int,
        containsTest: Bool,
        generation current: UInt64
    ) async {
        let now = await clock.now()
        guard current == generation, !Task.isCancelled else { return }
        var drops: [MonitoringDropReason: UInt64] = [:]
        switch result {
        case .accepted, .partial, .warning:
            retirePayload()
            state.state = .idle
            state.lastAccepted = now.date
            state.failure = nil
            state.warning = nil
            retryAttempt = 0
            if case .partial(let rejected) = result {
                drops[.partialRejection] = min(UInt64(count), rejected)
                state.warning = .partialRejection
            } else if result == .warning {
                state.warning = .receiverWarning
            }
        case .permanent(let failure):
            retirePayload()
            state.state = .failed
            state.failure = failure
            state.warning = nil
            retryAttempt = 0
            drops[.rejected] = UInt64(count)
        case .retryable(let failure):
            if signal == .metrics, metricVersion > activeMetricVersion {
                activeMetrics.removeAll(keepingCapacity: false)
            }
            let delay = OTLPRetryPolicy.delay(
                attempt: retryAttempt, retryAfter: retryAfter, now: now.date, jitter: jitter())
            retryAttempt = min(30, retryAttempt + 1)
            retrySchedule = MonitoringExportRetrySchedule(delay: delay, now: now)
            state.nextRetry = retrySchedule?.date
            state.state = .retrying
            state.failure = failure
            state.warning = .deliveryUncertain
        case .cancelled:
            retirePayload()
            state.state = .idle
            state.warning = .deliveryUncertain
            drops[.transportFailure] = UInt64(count)
        }
        if containsTest || state.state == .retrying { finishTest(result.testOutcome) }
        if testEventID == nil, testMetricVersion == nil, !finishing { forceFlush = false }
        checkTestRetention()
        await record(drops)
        guard current == generation else { return }
        if signal == .metrics, retrySchedule != nil, metricVersion > activeMetricVersion {
            activeMetrics.removeAll(keepingCapacity: false)
        }
        sendTask = nil
        wake()
    }

    private func retirePayload() {
        if signal == .logs {
            logs.finishBatch()
        } else if !activeMetrics.isEmpty {
            activeMetrics.removeFirst()
        }
    }
}

extension OTLPExportResult {
    fileprivate var testOutcome: MonitoringExportTestOutcome {
        switch self {
        case .accepted: .accepted
        case .partial(let rejected): .partial(rejected: rejected)
        case .warning: .warning
        case .retryable(let failure): .retrying(failure)
        case .permanent(let failure): .failed(failure)
        case .cancelled: .cancelled
        }
    }
}
