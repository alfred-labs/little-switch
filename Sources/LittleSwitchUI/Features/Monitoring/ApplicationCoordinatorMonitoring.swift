import Foundation
import LittleSwitchCore

extension ApplicationCoordinator {
    public func setMonitoringDraft(_ draft: MonitoringPendingSettings?) async -> CoordinatorSnapshot {
        monitoringDraftGeneration &+= 1
        pendingMonitoringSettings = draft?.matches(configuration.monitoring) == true ? nil : draft
        return await snapshot()
    }

    public func applyMonitoring(_ input: MonitoringApplyInput) async throws -> CoordinatorSnapshot {
        guard !monitoringApplyInProgress, !monitoringTestInProgress else { throw MonitoringSettingsError.busy }
        monitoringApplyInProgress = true
        do {
            try await commitMonitoring(input)
        } catch {
            monitoringApplyInProgress = false
            throw error
        }
        monitoringApplyInProgress = false
        return await snapshot()
    }

    private func commitMonitoring(_ input: MonitoringApplyInput) async throws {
        let generation = monitoringDraftGeneration
        let previous = configuration.monitoring
        var proposed = input
        // A stale pane may hold retired references. Only the currently applied accounts can be kept.
        proposed.configuration.metrics.credentialID = previous.metrics.credentialID
        proposed.configuration.logs.credentialID = previous.logs.credentialID
        try proposed.validate()
        monitoringNotice = nil
        var created: [UUID] = []
        let metricsBearer: String?
        let logsBearer: String?
        do {
            metricsBearer = try stageMonitoringCredential(
                &proposed.configuration.metrics,
                intent: proposed.metricsCredential,
                signal: .metrics,
                created: &created
            )
            logsBearer = try stageMonitoringCredential(
                &proposed.configuration.logs,
                intent: proposed.logsCredential,
                signal: .logs,
                created: &created
            )
        } catch {
            discardMonitoringCredentials(created)
            throw error
        }
        var saved = configuration
        saved.monitoring = proposed.configuration
        do {
            try saved.monitoring.validate()
            try configurationStore.save(saved)
        } catch {
            discardMonitoringCredentials(created)
            throw MonitoringSettingsError.saveFailed
        }
        configuration = saved
        monitoringTestResult = nil
        await monitoringExporter.configure(saved.monitoring, metricsBearer: metricsBearer, logsBearer: logsBearer)
        let retained = Set(
            [saved.monitoring.metrics.credentialID, saved.monitoring.logs.credentialID].compactMap(\.self))
        let retired = [previous.metrics.credentialID, previous.logs.credentialID].compactMap(\.self).filter {
            !retained.contains($0)
        }
        discardMonitoringCredentials(retired)
        if generation == monitoringDraftGeneration { pendingMonitoringSettings = nil }
    }

    public func testMonitoringExport() async -> CoordinatorSnapshot {
        guard !monitoringApplyInProgress, !monitoringTestInProgress, pendingMonitoringSettings == nil else {
            return await snapshot()
        }
        let tested = configuration.monitoring
        guard tested.metrics.enabled || tested.logs.enabled else { return await snapshot() }
        monitoringTestInProgress = true
        let result = await monitoringExporter.testExport()
        if configuration.monitoring == tested { monitoringTestResult = result }
        monitoringTestInProgress = false
        return await snapshot()
    }

    package func monitoringStatusSnapshot() async -> MonitoringExportStatus {
        var status = await monitoringExporter.status()
        status.isTesting = monitoringTestInProgress || status.isTesting
        return status
    }

    package func startMonitoring() async {
        let current = configuration.monitoring
        let metrics = savedMonitoringBearer(current.metrics)
        let logs = savedMonitoringBearer(current.logs)
        await monitoringExporter.configure(current, metricsBearer: metrics, logsBearer: logs)
    }

    private func savedMonitoringBearer(_ destination: MonitoringDestination) -> String? {
        guard destination.enabled, destination.authentication == .bearer, let id = destination.credentialID else {
            return nil
        }
        return try? secretStore.read(account: .monitoring(id))
    }

    package var gatewayMonitoring: GatewayMonitoring {
        let exporter = monitoringExporter
        return GatewayMonitoring(
            store: exporter.store,
            configuration: { await exporter.configuration },
            recordLog: { await exporter.enqueue($0) }
        )
    }

    private func stageMonitoringCredential(
        _ destination: inout MonitoringDestination,
        intent: MonitoringCredentialIntent,
        signal: MonitoringSignal,
        created: inout [UUID]
    ) throws -> String? {
        switch intent.normalized {
        case .keep: break
        case .remove: destination.credentialID = nil
        case .replace(let token):
            let credentialID = UUID()
            created.append(credentialID)
            do { try secretStore.write(token, account: .monitoring(credentialID)) } catch {
                throw MonitoringSettingsError.credentialWriteFailed
            }
            destination.credentialID = credentialID
        }
        guard destination.enabled, destination.authentication == .bearer else { return nil }
        guard let credentialID = destination.credentialID,
            let token = try? secretStore.read(account: .monitoring(credentialID)), !token.isEmpty
        else { throw MonitoringSettingsError.missingToken(signal) }
        guard token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw MonitoringSettingsError.invalidToken(signal)
        }
        return token
    }

    private func discardMonitoringCredentials(_ credentialIDs: [UUID]) {
        for credentialID in Set(credentialIDs) {
            do { try secretStore.delete(account: .monitoring(credentialID)) } catch {
                monitoringNotice = "An unused monitoring token could not be removed from Keychain."
            }
        }
    }
}
