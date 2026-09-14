import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Menu Apply dispatch")
struct MenuApplyActionDispatchTests {
    @Test("Codex rejects Apply when its explicit approval reviewer is unavailable")
    func codexRejectsUnavailableReviewer() async {
        let model = AppModel()
        model.hasPendingCodexChanges = true
        model.configuration.codex.autoReviewModel = ModelMapping(providerID: UUID(), modelID: "missing")
        var calls = 0
        let action = MenuApplyAction.codex(model: model) { calls += 1 }

        #expect(!action.isEnabled)
        action()
        for _ in 0..<20 { await Task.yield() }
        #expect(calls == 0)
    }

    @Test("Claude captures both operations before closing menu tracking")
    func claudeCapturesOperationsBeforeClosing() async {
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "qwen")]
        )
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: AppConfiguration(
                    providers: [provider],
                    mappings: [
                        "claude-sonnet-5": ModelMapping(providerID: provider.id, modelID: "qwen")
                    ]
                )
            )
        )
        model.claudeCodeStatus = .recoveryAvailable
        var order: [String] = []
        await confirmation("Both selected operations are dispatched once") { applied in
            let action = MenuApplyAction.claude(
                model: model,
                cancelTracking: {
                    order.append("closed")
                    // Closing can synchronously change presentation state.
                    model.configuration.connected = true
                    model.claudeCodeStatus = .disconnected
                    model.isBusy = true
                },
                onApply: { desktop, code in
                    #expect(order == ["closed"])
                    #expect(desktop == .connect)
                    #expect(code == .restore)
                    order.append("applied")
                    applied()
                }
            )
            action()
            #expect(order == ["closed"])
            for _ in 0..<20 where order.count < 2 {
                await Task.yield()
            }
        }
        #expect(order == ["closed", "applied"])
    }

    @Test("Mapping-only Apply carries no unrelated product operation")
    func mappingOnlyApply() async {
        let model = AppModel()
        model.hasPendingClaudeMappings = true
        var didApply = false
        var closed = false
        await confirmation("Mappings are applied once") { applied in
            let action = MenuApplyAction.claude(
                model: model,
                cancelTracking: { closed = true },
                onApply: { desktop, code in
                    #expect(closed)
                    #expect(desktop == nil)
                    #expect(code == nil)
                    didApply = true
                    applied()
                }
            )
            action()
            for _ in 0..<20 where !didApply {
                await Task.yield()
            }
        }
    }

    @Test("Codex dispatches once and rejects a stale activation while busy")
    func codexRechecksBusyState() async {
        let model = AppModel()
        model.hasPendingCodexChanges = true
        var calls = 0
        await confirmation("Codex is applied once") { applied in
            let action = MenuApplyAction.codex(model: model) {
                calls += 1
                applied()
            }
            action()
            model.isBusy = true
            action()
            for _ in 0..<20 where calls == 0 {
                await Task.yield()
            }
        }
        #expect(calls == 1)
    }
}
