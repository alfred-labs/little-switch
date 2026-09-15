import Foundation

public enum MonitoringExportState: String, Equatable, Sendable {
    case disabled, idle, sending, retrying, failed
}

public enum MonitoringExportWarning: Equatable, Sendable {
    case partialRejection
    case receiverWarning
    case deliveryUncertain
}

public enum MonitoringExportConfigurationIssue: Equatable, Sendable {
    case invalidInterval
    case invalidEndpoint
    case missingCredential
}

public struct MonitoringSignalExportStatus: Equatable, Sendable {
    public var state: MonitoringExportState
    public var lastAccepted: Date?
    public var nextRetry: Date?
    public var queuedCount: Int
    public var queuedBytes: Int
    public var drops: [MonitoringDropReason: UInt64]
    public var failure: OTLPExportFailure?
    public var warning: MonitoringExportWarning?
    public var configurationIssue: MonitoringExportConfigurationIssue?

    public var droppedCount: UInt64 { drops.values.reduce(0, monitoringSum) }

    public init(
        state: MonitoringExportState = .disabled,
        lastAccepted: Date? = nil,
        nextRetry: Date? = nil,
        queuedCount: Int = 0,
        queuedBytes: Int = 0,
        drops: [MonitoringDropReason: UInt64] = [:],
        failure: OTLPExportFailure? = nil,
        warning: MonitoringExportWarning? = nil,
        configurationIssue: MonitoringExportConfigurationIssue? = nil
    ) {
        self.state = state
        self.lastAccepted = lastAccepted
        self.nextRetry = nextRetry
        self.queuedCount = queuedCount
        self.queuedBytes = queuedBytes
        self.drops = drops
        self.failure = failure
        self.warning = warning
        self.configurationIssue = configurationIssue
    }
}

public struct MonitoringExportStatus: Equatable, Sendable {
    public var metrics: MonitoringSignalExportStatus
    public var logs: MonitoringSignalExportStatus
    public var isTesting: Bool

    public init(
        metrics: MonitoringSignalExportStatus = .init(),
        logs: MonitoringSignalExportStatus = .init(),
        isTesting: Bool = false
    ) {
        self.metrics = metrics
        self.logs = logs
        self.isTesting = isTesting
    }
}

public enum MonitoringExportTestOutcome: Equatable, Sendable {
    case disabled
    case accepted
    case partial(rejected: UInt64)
    case warning
    case retrying(OTLPExportFailure)
    case failed(OTLPExportFailure)
    case invalidConfiguration(MonitoringExportConfigurationIssue)
    case cancelled
}

public struct MonitoringExportTestResult: Equatable, Sendable {
    public let metrics: MonitoringExportTestOutcome
    public let logs: MonitoringExportTestOutcome

    public init(metrics: MonitoringExportTestOutcome = .disabled, logs: MonitoringExportTestOutcome = .disabled) {
        self.metrics = metrics
        self.logs = logs
    }
}
