import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Monitoring settings draft")
struct MonitoringSettingsDraftTests {
    @Test("A reopened pane adopts applied credentials while keeping current fields and typed tokens")
    func rebaseAfterNavigation() {
        let previous = MonitoringConfiguration()
        var applied = MonitoringConfiguration(
            metrics: .init(enabled: true, endpoint: "https://receiver.example/v1/metrics", authentication: .bearer))
        var reopened = MonitoringSettingsDraft(configuration: applied)
        applied.metrics.credentialID = UUID()
        reopened.rebase(on: applied, replacing: previous)
        #expect(!reopened.hasChanges(from: applied))
        #expect(reopened.validationMessage == nil)
        var pristine = MonitoringSettingsDraft(configuration: previous)
        pristine.rebase(on: applied, replacing: previous)
        #expect(pristine.configuration == applied)
        reopened.metricsToken = "newer-synthetic"
        reopened.configuration.logs.endpoint = "https://newer.example/v1/logs"
        reopened.rebase(on: applied, replacing: previous)
        #expect(reopened.metricsToken == "newer-synthetic")
        #expect(reopened.configuration.logs.endpoint == "https://newer.example/v1/logs")
    }

    @Test("Acknowledging Apply preserves newer edits and only clears the submitted tokens")
    func newerEditsAfterApply() {
        var draft = MonitoringSettingsDraft(configuration: .init())
        draft.metricsToken = "submitted-synthetic"
        draft.logsToken = "unchanged-synthetic"
        let submitted = draft.input
        draft.metricsToken = "newer-synthetic"
        draft.configuration.logs.endpoint = "https://newer.example/v1/logs"
        var applied = submitted.configuration
        applied.metrics.credentialID = UUID()
        applied.logs.credentialID = UUID()
        draft.acknowledge(applied, submitted: submitted)
        #expect(draft.metricsToken == "newer-synthetic")
        #expect(draft.logsToken.isEmpty)
        #expect(draft.configuration.logs.endpoint == "https://newer.example/v1/logs")
        #expect(draft.configuration.metrics.credentialID == applied.metrics.credentialID)
        let latest = draft.input
        draft.acknowledge(applied, submitted: latest)
        #expect(draft == MonitoringSettingsDraft(configuration: applied))
    }

    @Test("The draft restores only non-secret pending values")
    func restoredDraft() {
        let pending = MonitoringConfiguration(exposeLogs: true)
        let draft = MonitoringSettingsDraft(configuration: .init(), pending: .init(configuration: pending))
        #expect(draft.input.configuration == pending)
        #expect(draft.metricsToken.isEmpty && draft.logsToken.isEmpty)
        #expect(draft.hasChanges(from: .init()))
    }

    @Test("Blank keeps a saved token, replacement and removal remain explicit")
    func credentialIntents() {
        var draft = MonitoringSettingsDraft(configuration: .init())
        draft.metricsToken = " \n "
        #expect(draft.input.metricsCredential == .keep)
        draft.logsToken = " new-token "
        #expect(draft.input.logsCredential == .replace("new-token"))
        #expect(draft.hasChanges(from: .init()))
        draft.removeMetricsToken = true
        #expect(draft.input.metricsCredential == .remove)
        draft.clearTypedTokens()
        #expect(draft.metricsToken.isEmpty && draft.logsToken.isEmpty)
        #expect(draft.removeMetricsToken && !draft.removeLogsToken)
    }

    @Test("Apply validation requires complete destinations and an available bearer token")
    func validation() {
        var draft = MonitoringSettingsDraft(configuration: .init())
        #expect(draft.validationMessage == nil)
        draft.configuration.metrics.enabled = true
        #expect(draft.validationMessage != nil)
        draft.configuration.metrics.endpoint = "http://localhost:19090/api/v1/otlp/v1/metrics"
        #expect(draft.validationMessage == nil)
        draft.configuration.metrics.authentication = .bearer
        #expect(draft.validationMessage != nil)
        draft.metricsToken = "synthetic-token"
        #expect(draft.validationMessage == nil)
        draft.metricsToken = "bad\nheader"
        #expect(draft.validationMessage != nil)
    }
}
