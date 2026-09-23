import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Claude Desktop pending catalog presentation")
struct ClaudeDesktopPendingPresentationTests {
    @Test("A pending Desktop catalog enables Apply until the refreshed snapshot settles it")
    func pendingCatalogAction() {
        let model = AppModel(snapshot: snapshot(desktopPending: true))

        #expect(model.claudePrimaryAction == .apply)
        #expect(model.canPerformClaudePrimaryAction)
        #expect(model.canApplyClaudeProducts)
        #expect(model.claudePrimaryActionAccessibilityValue == L10n.string("Pending in Claude"))
        #expect(
            model.claudePrimaryActionAccessibilityHint
                == L10n.string("Updates the model list in Claude Desktop and restarts it if it is running"))

        model.apply(snapshot(desktopPending: false))

        #expect(model.claudePrimaryAction == nil)
        #expect(!model.canPerformClaudePrimaryAction)
        #expect(!model.canApplyClaudeProducts)
        #expect(model.claudePrimaryActionAccessibilityValue == L10n.string("No pending changes"))
    }

    @Test("Desktop catalog Apply remains blocked while busy or organization managed")
    func pendingCatalogAvailability() {
        let model = AppModel(snapshot: snapshot(desktopPending: true))
        #expect(model.canPerformClaudePrimaryAction)
        model.isBusy = true
        #expect(!model.canPerformClaudePrimaryAction)
        model.isBusy = false
        model.desktopApplications.claude = .organizationManaged
        #expect(!model.canPerformClaudePrimaryAction)
        #expect(model.claudePrimaryActionAccessibilityValue == L10n.string("Pending in Claude"))
    }

    @Test("The shared Apply hint promises a Desktop restart only when Desktop Apply is available")
    func sharedApplyHint() {
        let model = AppModel(snapshot: snapshot(desktopPending: true))
        #expect(
            model.claudeProductsApplyAccessibilityHint
                == L10n.string("Updates the model list in Claude Desktop and restarts it if it is running"))

        model.apply(snapshot(desktopPending: false))
        model.hasPendingClaudeMappings = true
        #expect(model.canApplyClaudeProducts)
        #expect(
            model.claudeProductsApplyAccessibilityHint
                == L10n.string("Applies pending settings and connects Claude apps"))

        model.apply(snapshot(desktopPending: true))
        model.desktopApplications.claude = .organizationManaged
        model.hasPendingClaudeCodeChanges = true
        model.claudeCodeMappedRouteIDs = ["claude-sonnet-5"]
        #expect(model.canApplyClaudeProducts)
        #expect(!model.canPerformClaudePrimaryAction)
        #expect(
            model.claudeProductsApplyAccessibilityHint
                == L10n.string("Applies pending settings and connects Claude apps"))
    }

    @Test("Saved catalog changes prompt on quit without being called discarded drafts")
    func savedCatalogWarning() {
        let model = AppModel(snapshot: snapshot(desktopPending: true))

        #expect(model.hasPendingChanges)
        #expect(model.pendingChangeNames.isEmpty)
        #expect(
            model.pendingChangesWarning
                == L10n.string("The model list still needs to be applied in Claude Desktop."))

        model.hasPendingClaudeMappings = true
        #expect(model.pendingChangeNames == [L10n.string("Claude")])
        let discardWarning = L10n.string("Unapplied changes for \(L10n.string("Claude")) will be discarded.")
        let desktopWarning = L10n.string("The model list still needs to be applied in Claude Desktop.")
        #expect(
            model.pendingChangesWarning
                == L10n.string("\(discardWarning) \(desktopWarning)"))
    }

    @Test("The menu forwards Desktop catalog Apply while mapping-only Apply stays lightweight")
    func menuDispatch() async throws {
        let model = AppModel(snapshot: snapshot(desktopPending: true))
        var dispatched: [(AppModel.ClaudePrimaryAction?, AppModel.ClaudeCodePrimaryAction?)] = []
        var cancelledTracking = 0
        let action = MenuApplyAction.claude(
            model: model,
            cancelTracking: { cancelledTracking += 1 },
            onApply: { desktop, code in
                dispatched.append((desktop, code))
            }
        )
        #expect(action.isEnabled)
        action()
        _ = try await eventually(description: "Desktop catalog Apply dispatch") {
            await MainActor.run { dispatched.count == 1 ? true : nil }
        }
        #expect(dispatched.first?.0 == .apply)
        #expect(dispatched.first?.1 == nil)
        #expect(cancelledTracking == 1)

        model.apply(snapshot(desktopPending: false))
        model.hasPendingClaudeMappings = true
        #expect(action.isEnabled)
        action()
        _ = try await eventually(description: "Mapping-only Apply dispatch") {
            await MainActor.run { dispatched.count == 2 ? true : nil }
        }
        #expect(dispatched.last?.0 == nil)
        #expect(dispatched.last?.1 == nil)
        #expect(cancelledTracking == 2)
    }

    private func snapshot(desktopPending: Bool) -> CoordinatorSnapshot {
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:12345",
            authMode: .none,
            models: [DiscoveredModel(id: "model")]
        )
        return CoordinatorSnapshot(
            configuration: AppConfiguration(
                providers: [provider],
                mappings: ["claude-sonnet-5": ModelMapping(providerID: provider.id, modelID: "model")],
                connected: true
            ),
            desktopApplications: .init(claude: .available),
            hasPendingClaudeDesktopChanges: desktopPending,
            claudeCodeStatus: .connected
        )
    }
}
