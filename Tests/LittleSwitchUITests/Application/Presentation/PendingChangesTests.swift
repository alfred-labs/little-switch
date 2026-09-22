import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchSearch
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Pending changes")
struct PendingChangesTests {
    @Test("Every draft is named, in reading order, and only when it exists")
    func pendingNames() {
        let model = AppModel()

        #expect(model.pendingChangeNames.isEmpty)
        #expect(!model.hasPendingChanges)
        #expect(model.pendingChangesWarning == nil)

        model.hasPendingClaudeMappings = true
        model.hasPendingCodexChanges = true
        #expect(model.pendingChangeNames == [L10n.string("Claude"), L10n.string("Codex")])

        model.hasPendingClaudeCodeChanges = true
        model.hasPendingOpenCodeChanges = true
        model.webSearchDraft = WebSearchPendingSettings(configuration: WebSearchConfiguration())
        #expect(
            model.pendingChangeNames == [
                L10n.string("Claude"), L10n.string("Claude Code"), L10n.string("Codex"), L10n.string("OpenCode"),
                L10n.string("Web search"),
            ]
        )
        #expect(
            model.pendingChangesWarning
                == L10n.string(
                    "Unapplied changes for \(AppModel.list(model.pendingChangeNames)) will be discarded."
                )
        )
    }

    @Test("A snapshot carries the web search draft into the model")
    func snapshotCarriesDraft() {
        let draft = WebSearchPendingSettings(configuration: WebSearchConfiguration(provider: .firecrawl))
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: AppConfiguration(),
                webSearchDraft: draft
            )
        )

        #expect(model.webSearchDraft == draft)
        #expect(model.pendingChangeNames == [L10n.string("Web search")])

        model.apply(CoordinatorSnapshot(configuration: AppConfiguration()))
        #expect(model.webSearchDraft == nil)
    }

    @Test("A draft that would write nothing is not pending")
    func draftMatchesSavedConfiguration() {
        let saved = WebSearchConfiguration(provider: .firecrawl)
        let unchanged = WebSearchInput(configuration: saved)
        let blankCredential = WebSearchInput(configuration: saved, credential: "   ")
        let newCredential = WebSearchInput(configuration: saved, credential: "fc-key")
        let changed = WebSearchInput(configuration: WebSearchConfiguration(provider: .disabled))

        #expect(unchanged.matches(saved))
        #expect(blankCredential.matches(saved))
        #expect(!newCredential.matches(saved))
        #expect(!changed.matches(saved))
    }

    @Test("A stored draft survives the pane and drops the typed credential")
    func draftRestoration() {
        let saved = WebSearchConfiguration(provider: .disabled)
        let pending = WebSearchPendingSettings(
            configuration: WebSearchConfiguration(provider: .firecrawl, resultsLimit: 7),
            hasTypedCredential: true
        )

        let restored = WebSearchDraft(configuration: saved, pending: pending)
        let withoutPending = WebSearchDraft(configuration: saved, pending: nil)

        #expect(restored.provider == .firecrawl)
        #expect(restored.resultsLimit == 7)
        #expect(restored.credential.isEmpty)
        #expect(withoutPending.provider == .disabled)
    }

    @Test("The name list reads as a sentence at every length")
    func nameList() {
        #expect(AppModel.list([]).isEmpty)
        #expect(AppModel.list([L10n.string("Codex")]) == L10n.string("Codex"))
        #expect(
            AppModel.list([L10n.string("Codex"), L10n.string("OpenCode")])
                == ListFormatter.localizedString(
                    byJoining: [L10n.string("Codex"), L10n.string("OpenCode")]
                )
        )
        #expect(
            AppModel.list([L10n.string("Claude Desktop"), L10n.string("Codex"), L10n.string("OpenCode")])
                == ListFormatter.localizedString(
                    byJoining: [
                        L10n.string("Claude Desktop"),
                        L10n.string("Codex"),
                        L10n.string("OpenCode"),
                    ]
                )
        )
    }

    @Test("The menu row says when an application holds unapplied changes")
    func menuDetailCopy() {
        #expect(
            StatusMenuCopy.detail("3 custom models", hasPendingChanges: false)
                == "3 custom models"
        )
        #expect(
            StatusMenuCopy.detail("3 custom models", hasPendingChanges: true)
                == L10n.string("\("3 custom models") · \(StatusMenuCopy.pendingChanges)")
        )
        #expect(StatusMenuCopy.customModelCount(1) == L10n.string("\(1) custom model"))
    }
}
