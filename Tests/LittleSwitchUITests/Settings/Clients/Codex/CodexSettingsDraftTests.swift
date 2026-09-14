import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Codex settings draft")
struct CodexSettingsDraftTests {
    @Test("A draft applies only Codex settings and normalizes its default")
    func applying() {
        let providerID = UUID()
        let first = ModelMapping(providerID: providerID, modelID: "first")
        let second = ModelMapping(providerID: providerID, modelID: "second")
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "first"), DiscoveredModel(id: "second")]
        )
        let configuration = AppConfiguration(
            providers: [provider],
            autoMode: false,
            codex: CodexConfiguration(connected: true, defaultModel: first)
        )
        var draft = CodexSettingsDraft(configuration: configuration)
        draft.defaultModel = first
        draft.excludedModels = [first]

        let applied = draft.applying(to: configuration)

        #expect(applied.autoMode == configuration.autoMode)
        #expect(applied.codex.connected)
        #expect(applied.codex.defaultModel == second)
        #expect(applied.codex.excludedModels == [first])
    }

    @Test("Reconciliation preserves stale exclusions and drops an unavailable default")
    func reconciliation() {
        let providerID = UUID()
        let stale = ModelMapping(providerID: providerID, modelID: "stale")
        let current = ModelMapping(providerID: providerID, modelID: "current")
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "current")]
        )
        let draft = CodexSettingsDraft(defaultModel: stale, excludedModels: [stale])

        #expect(
            draft.reconciled(providers: [provider])
                == CodexSettingsDraft(
                    defaultModel: current,
                    excludedModels: [stale]
                )
        )
    }
}
