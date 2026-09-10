import Foundation
import LittleSwitchCore

struct GatewayActivityPollingUpdate: Equatable, Sendable {
    let requestCount: Int
    let claudeRequestCount: Int
    let codexRequestCount: Int
    let activity: GatewayActivitySnapshot
    let usage: GatewayUsageSummary?
    let clientUsage: [GatewayClient: GatewayUsageSummary]?
    let responsesWireVerdicts: [UUID: Bool]
    let credentialRefreshFailures: [UUID: String]
    let lastScriptOutputs: [UUID: String]
    let monitoringStatus: MonitoringExportStatus
    let monitoringApplying: Bool
    let monitoringNotice: String?
    let monitoringTestResult: MonitoringExportTestResult?
    let monitoringHTTPSAvailable: Bool
    let monitoringConfiguration: MonitoringConfiguration
    let monitoringSnapshotSequence: UInt64

    init(
        snapshot: CoordinatorSnapshot,
        activity: GatewayActivitySnapshot,
        usage: GatewayUsageSummary? = nil,
        clientUsage: [GatewayClient: GatewayUsageSummary]? = nil,
        responsesWireVerdicts: [UUID: Bool] = [:]
    ) {
        requestCount = snapshot.requestCount
        claudeRequestCount = snapshot.claudeRequestCount
        codexRequestCount = snapshot.codexRequestCount
        self.activity = activity
        self.usage = usage
        self.clientUsage = clientUsage
        self.responsesWireVerdicts = responsesWireVerdicts
        self.credentialRefreshFailures = snapshot.credentialRefreshFailures
        self.lastScriptOutputs = snapshot.lastScriptOutputs
        monitoringStatus = snapshot.monitoringStatus
        monitoringApplying = snapshot.monitoringApplying
        monitoringNotice = snapshot.monitoringNotice
        monitoringTestResult = snapshot.monitoringTestResult
        monitoringHTTPSAvailable = snapshot.monitoringHTTPSAvailable
        monitoringConfiguration = snapshot.configuration.monitoring
        monitoringSnapshotSequence = snapshot.monitoringSnapshotSequence
    }

    static func load(
        from coordinator: ApplicationCoordinator,
        usageHistory: GatewayUsageHistoryStore? = nil
    ) async -> Self {
        let snapshot = await coordinator.snapshot()
        let activity = await coordinator.gatewayActivity()
        let usage = await usageHistory?.summary()
        let clientUsage = await usageHistory?.clientSummaries()
        let responsesWireVerdicts = await coordinator.responsesWireVerdicts()
        return Self(
            snapshot: snapshot,
            activity: activity,
            usage: usage,
            clientUsage: clientUsage,
            responsesWireVerdicts: responsesWireVerdicts
        )
    }

    @MainActor
    func apply(to model: AppModel) {
        model.requestCount = requestCount
        model.claudeRequestCount = claudeRequestCount
        model.codexRequestCount = codexRequestCount
        model.updateGatewayActivity(activity)
        model.updateGatewayUsage(usage)
        model.updateGatewayClientUsage(clientUsage)
        model.updateResponsesWireVerdicts(responsesWireVerdicts)
        model.updateCredentialRefreshFailures(credentialRefreshFailures)
        model.updateLastScriptOutputs(lastScriptOutputs)
        guard model.monitoringAction == nil,
            monitoringConfiguration == model.configuration.monitoring,
            monitoringSnapshotSequence >= model.monitoringSnapshotSequence
        else { return }
        model.monitoringStatus = monitoringStatus
        model.monitoringApplying = monitoringApplying
        model.monitoringNotice = monitoringNotice
        model.monitoringTestResult = monitoringTestResult
        model.monitoringHTTPSAvailable = monitoringHTTPSAvailable
        model.monitoringSnapshotSequence = monitoringSnapshotSequence
    }
}
