/// A view action stays busy until its own response arrives, independently of polling.
enum MonitoringAction: Equatable {
    case apply
    case test
}

extension LittleSwitchApplicationDelegate {
    func setMonitoringDraft(_ input: MonitoringPendingSettings?) async {
        guard let coordinator else { return }
        let snapshot = await coordinator.setMonitoringDraft(input)
        model.monitoringDraft = snapshot.monitoringDraft
    }

    func applyMonitoring(_ input: MonitoringApplyInput) async -> Bool {
        guard let coordinator, model.monitoringAction == nil else { return false }
        model.monitoringAction = .apply
        model.monitoringApplying = true
        defer { model.monitoringAction = nil }
        do {
            model.apply(try await coordinator.applyMonitoring(input))
            return true
        } catch {
            model.apply(await coordinator.snapshot())
            present(error)
            return false
        }
    }

    func testMonitoringExport() async {
        guard let coordinator, model.monitoringAction == nil else { return }
        model.monitoringAction = .test
        defer { model.monitoringAction = nil }
        model.monitoringStatus.isTesting = true
        model.apply(await coordinator.testMonitoringExport())
    }
}
