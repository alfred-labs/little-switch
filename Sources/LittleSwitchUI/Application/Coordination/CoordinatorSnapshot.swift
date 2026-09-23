import Foundation
import LittleSwitchCommon
import LittleSwitchCore

public struct CoordinatorSnapshot: Equatable, Sendable {
    public var configuration: AppConfiguration
    public var desktopApplications: DesktopApplicationAvailability
    public var requestCount: Int
    public var claudeRequestCount: Int
    public var codexRequestCount: Int
    public var proxyRunning: Bool
    public var hasPendingCodexChanges: Bool
    /// Claude route mappings edited while connected, waiting for Apply.
    public var hasPendingClaudeMappings: Bool
    public var hasPendingClaudeDesktopChanges: Bool
    public var claudeCodeStatus: ClaudeCodeConnectionStatus
    public var hasPendingClaudeCodeChanges: Bool
    public var claudeCodeMappedRouteIDs: [String]
    public var openCodeStatus: OpenCodeConnectionStatus
    public var hasPendingOpenCodeChanges: Bool
    public var webSearchDraft: WebSearchPendingSettings?
    public var webSearchDraftRevision: UInt64
    public var monitoringDraft: MonitoringPendingSettings?
    public var monitoringStatus: MonitoringExportStatus
    public var monitoringApplying: Bool
    public var monitoringNotice: String?
    public var monitoringTestResult: MonitoringExportTestResult?
    public var monitoringHTTPSAvailable: Bool
    public var monitoringSnapshotSequence: UInt64
    /// Last failure of each provider's scheduled credential script, keyed by
    /// provider. Absent or empty means the script is healthy or not scheduled.
    public var credentialRefreshFailures: [UUID: String]
    /// Stderr tail of each provider's last credential script run, keyed by
    /// provider — successes included; the editor replays it in its output pane.
    public var lastScriptOutputs: [UUID: String]
    public var imageProbeProgress: [UUID: ProviderImageProbeProgress]
    public var responsesWireVerdicts: [UUID: Bool] = [:]
    package var imageInputDiagnostics: [ModelImageInputProbeDiagnostic] = []
    package var imageInputPersistenceFailures: Set<UUID> = []

    public init(
        configuration: AppConfiguration,
        desktopApplications: DesktopApplicationAvailability = .init(),
        requestCount: Int = 0,
        claudeRequestCount: Int = 0,
        codexRequestCount: Int = 0,
        proxyRunning: Bool = false,
        hasPendingCodexChanges: Bool = false,
        hasPendingClaudeMappings: Bool = false,
        hasPendingClaudeDesktopChanges: Bool = false,
        claudeCodeStatus: ClaudeCodeConnectionStatus = .disconnected,
        hasPendingClaudeCodeChanges: Bool = false,
        claudeCodeMappedRouteIDs: [String] = [],
        openCodeStatus: OpenCodeConnectionStatus = .disconnected,
        hasPendingOpenCodeChanges: Bool = false,
        webSearchDraft: WebSearchPendingSettings? = nil,
        webSearchDraftRevision: UInt64 = 0,
        monitoringDraft: MonitoringPendingSettings? = nil,
        monitoringStatus: MonitoringExportStatus = .init(),
        monitoringApplying: Bool = false,
        monitoringNotice: String? = nil,
        monitoringTestResult: MonitoringExportTestResult? = nil,
        monitoringHTTPSAvailable: Bool = false,
        monitoringSnapshotSequence: UInt64 = 0,
        credentialRefreshFailures: [UUID: String] = [:],
        lastScriptOutputs: [UUID: String] = [:],
        imageProbeProgress: [UUID: ProviderImageProbeProgress] = [:]
    ) {
        self.configuration = configuration
        self.desktopApplications = desktopApplications
        self.requestCount = requestCount
        self.claudeRequestCount = claudeRequestCount
        self.codexRequestCount = codexRequestCount
        self.proxyRunning = proxyRunning
        self.hasPendingCodexChanges = hasPendingCodexChanges
        self.hasPendingClaudeMappings = hasPendingClaudeMappings
        self.hasPendingClaudeDesktopChanges = hasPendingClaudeDesktopChanges
        self.claudeCodeStatus = claudeCodeStatus
        self.hasPendingClaudeCodeChanges = hasPendingClaudeCodeChanges
        self.claudeCodeMappedRouteIDs = claudeCodeMappedRouteIDs
        self.openCodeStatus = openCodeStatus
        self.hasPendingOpenCodeChanges = hasPendingOpenCodeChanges
        self.webSearchDraft = webSearchDraft
        self.webSearchDraftRevision = webSearchDraftRevision
        self.monitoringDraft = monitoringDraft
        self.monitoringStatus = monitoringStatus
        self.monitoringApplying = monitoringApplying
        self.monitoringNotice = monitoringNotice
        self.monitoringTestResult = monitoringTestResult
        self.monitoringHTTPSAvailable = monitoringHTTPSAvailable
        self.monitoringSnapshotSequence = monitoringSnapshotSequence
        self.credentialRefreshFailures = credentialRefreshFailures
        self.lastScriptOutputs = lastScriptOutputs
        self.imageProbeProgress = imageProbeProgress
    }
}
