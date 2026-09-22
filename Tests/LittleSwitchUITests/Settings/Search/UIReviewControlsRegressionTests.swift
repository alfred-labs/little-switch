import AppKit
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchSearch
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("UI review control regressions", .appKitIsolation)
struct UIReviewControlsRegressionTests {
    @Test("Web search edits enter the discard warning before the pane closes")
    func searchEditsArePendingWhileVisible() async throws {
        let model = AppModel()
        let host = searchHost(model)
        defer { host.close() }
        try await host.activateAccessibility()

        #expect(try host.element(label: L10n.string("Tavily")).accessibilityPerformPress())
        _ = try await eventually(description: "visible search draft is published") {
            await MainActor.run {
                host.render()
                return model.hasPendingChanges ? true : nil
            }
        }
        #expect(model.pendingChangeNames == [L10n.string("Web search")])
        #expect(model.webSearchDraft?.configuration.provider == .tavily)
    }

    @Test("A typed search credential remains pending and survives a snapshot refresh")
    func searchCredentialDraftSurvivesRefresh() async throws {
        let configuration = AppConfiguration(webSearch: WebSearchConfiguration(provider: .tavily))
        let model = AppModel(snapshot: CoordinatorSnapshot(configuration: configuration))
        let host = searchHost(model)
        defer { host.close() }
        let field = try #require(descendant(NSSecureTextField.self, in: host.hosting))
        #expect(host.window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("synthetic-key", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))

        _ = try await eventually(description: "credential-only edit enters discard warning") {
            await MainActor.run {
                host.render()
                return model.hasPendingChanges ? true : nil
            }
        }
        var refreshed = configuration
        refreshed.webSearch.resultsLimit += 1
        model.apply(CoordinatorSnapshot(configuration: refreshed, webSearchDraft: model.webSearchDraft))
        host.render()
        #expect(try #require(descendant(NSSecureTextField.self, in: host.hosting)).stringValue == "synthetic-key")
    }

    @Test("A rejected menu selection returns to the authoritative model without closing the menu")
    func rejectedMenuSelection() async throws {
        let model = menuModel()
        var completed = false
        let host = MenuControlTestHost(
            Grid {
                MenuCodexReviewModelRow(model: model) { _ in completed = true }
            }, width: 360)
        defer { host.close() }
        try await host.activateAccessibility()
        #expect(try host.element(label: nextReviewLabel).accessibilityPerformPress())
        _ = try await eventually(description: "rejected selection completes") {
            await MainActor.run { completed ? true : nil }
        }
        host.render()
        #expect(host.textContent.contains(L10n.string("Same as default")))
    }

    @Test("An older menu completion cannot erase a newer click, whose failure restores the accepted choice")
    func overlappingMenuSelections() async throws {
        let model = menuModel()
        let changes = PendingMenuSelections(model: model)
        let host = MenuControlTestHost(
            Grid { MenuCodexReviewModelRow(model: model, onSelect: changes.select) }, width: 360)
        defer {
            host.close()
            changes.finishAll()
        }
        try await host.activateAccessibility()
        #expect(try host.element(label: nextReviewLabel).accessibilityPerformPress())
        try await changes.waitForCount(1)
        host.render()
        #expect(try host.element(label: nextReviewLabel).accessibilityPerformPress())
        host.render()
        let newestLabel = try #require(model.modelOptions.last?.label)
        #expect(host.textContent.contains(newestLabel))

        changes.finishFirst(accepting: true)
        try await changes.waitForCount(1)
        host.render()
        #expect(host.textContent.contains(newestLabel))

        changes.finishFirst(accepting: false)
        _ = try await eventually(description: "latest menu rejection restores the accepted model") {
            await MainActor.run {
                host.render()
                return host.textContent.contains(model.modelOptions[0].label) ? true : nil
            }
        }
    }

    private var nextReviewLabel: String {
        L10n.string("Next model for \(L10n.string("Custom approval review model"))")
    }

    private func searchHost(_ model: AppModel) -> MenuControlTestHost<WebSearchSettingsView> {
        MenuControlTestHost(
            WebSearchSettingsView(
                model: model,
                onSave: { _ in false },
                onDraft: { pending in
                    model.apply(CoordinatorSnapshot(configuration: model.configuration, webSearchDraft: pending))
                }),
            width: 700,
            height: 600)
    }

    private func menuModel() -> AppModel {
        AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: AppConfiguration(providers: [
                    Provider(
                        name: "Local",
                        baseURL: "http://127.0.0.1:11434",
                        authMode: .none,
                        models: [DiscoveredModel(id: "alpha"), DiscoveredModel(id: "beta")],
                        status: .ready)
                ])))
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        (view as? T) ?? view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }
}

@MainActor
private final class PendingMenuSelections {
    let model: AppModel
    private var pending: [(ModelMapping?, CheckedContinuation<Bool, Never>)] = []
    private var isFinishing = false

    init(model: AppModel) { self.model = model }

    func select(_ mapping: ModelMapping?) async {
        guard !isFinishing else { return }
        let accepted = await withCheckedContinuation { pending.append((mapping, $0)) }
        if accepted { model.configuration.codex.autoReviewModel = mapping }
    }

    func waitForCount(_ count: Int) async throws {
        _ = try await eventually(description: "\(count) pending menu selections") {
            await MainActor.run { self.pending.count == count ? true : nil }
        }
    }

    func finishFirst(accepting: Bool) {
        pending.removeFirst().1.resume(returning: accepting)
    }

    func finishAll() {
        isFinishing = true
        let remaining = pending
        pending = []
        for item in remaining { item.1.resume(returning: false) }
    }
}
