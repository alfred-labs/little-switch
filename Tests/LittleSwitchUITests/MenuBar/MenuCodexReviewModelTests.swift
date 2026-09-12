import AppKit
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Codex menu approval review model")
struct MenuCodexReviewModelTests {
    @Test("Codex scopes the approval reviewer to custom models beside its default model")
    func reviewerIsAccessible() async throws {
        let model = makeModel().model
        model.configuration.codex.connected = false
        let host = MenuControlTestHost(
            MenuCodexTabView(model: model, onDefault: { _ in }, onAutoReview: { _ in }, onApplyCodex: {}),
            height: MenuCodexTabView.height
        )
        defer { host.close() }
        try await host.activateAccessibility()

        _ = try host.element(label: "Model for Custom approval review model")
        #expect(host.textContent.contains("Custom review"))
        #expect(host.textContent.contains("Same as default"))
        let apply = try host.element(label: "Apply changes")
        #expect(!apply.isAccessibilityEnabled())
        #expect(apply.object.accessibilityHelp?() == "Applies changes in this tab")
    }

    @Test("Reviewer selection includes unexposed models and applies through the existing action")
    func selectsReviewerAndDefault() async throws {
        let fixture = makeModel()
        let model = fixture.model
        var selections: [ModelMapping?] = []
        var defaultChanges = 0
        var applyCalls = 0
        let host = MenuControlTestHost(
            MenuCodexTabView(
                model: model,
                onDefault: { _ in defaultChanges += 1 },
                onAutoReview: {
                    selections.append($0)
                    model.configuration.codex.autoReviewModel = $0
                    model.hasPendingCodexChanges = true
                },
                onApplyCodex: { applyCalls += 1 }
            ),
            height: MenuCodexTabView.height
        )
        defer { host.close() }
        try await host.activateAccessibility()
        #expect(model.codexExposedModelOptions.map(\.mapping) == [fixture.primary])
        #expect(try !host.element(label: "Apply changes").isAccessibilityEnabled())

        for expectedCount in 1...3 {
            #expect(try host.element(label: "Next model for Custom approval review model").accessibilityPerformPress())
            for _ in 0..<20 where selections.count < expectedCount { await Task.yield() }
            host.render()
        }

        #expect(selections == [fixture.primary, fixture.reviewer, nil])
        #expect(model.configuration.codex.defaultModel == fixture.primary)
        #expect(defaultChanges == 0)
        #expect(applyCalls == 0)
        #expect(host.textContent.contains("Same as default"))
        #expect(try host.element(label: "Apply changes").accessibilityPerformPress())
        for _ in 0..<20 where applyCalls == 0 { await Task.yield() }
        #expect(applyCalls == 1)
    }

    @Test("An unavailable reviewer stays visible until it is replaced")
    func unavailableReviewer() async throws {
        let fixture = makeModel()
        let model = fixture.model
        model.configuration.codex.autoReviewModel = ModelMapping(providerID: UUID(), modelID: "removed")
        model.hasPendingCodexChanges = true
        var selections: [ModelMapping?] = []
        let host = MenuControlTestHost(
            MenuCodexTabView(
                model: model,
                onDefault: { _ in },
                onAutoReview: {
                    selections.append($0)
                    model.configuration.codex.autoReviewModel = $0
                },
                onApplyCodex: {}
            ),
            height: MenuCodexTabView.height
        )
        defer { host.close() }
        try await host.activateAccessibility()
        #expect(host.textContent.contains("Unavailable: removed"))
        #expect(host.textContent.contains("Review model unavailable"))
        #expect(try !host.element(label: "Apply changes").isAccessibilityEnabled())
        #expect(host.hosting.fittingSize.height == MenuCodexTabView.height)

        #expect(try host.element(label: "Next model for Custom approval review model").accessibilityPerformPress())
        for _ in 0..<20 where selections.isEmpty { await Task.yield() }
        host.render()
        #expect(selections == [nil])
        #expect(model.configuration.codex.autoReviewModel == nil)
        #expect(host.textContent.contains("Same as default"))
        #expect(try host.element(label: "Apply changes").isAccessibilityEnabled())
    }

    @Test("Busy and empty catalogs disable reviewer controls")
    func disabledReviewer() async throws {
        let busy = makeModel().model
        busy.isBusy = true
        for model in [AppModel(), busy] {
            var calls = 0
            let host = MenuControlTestHost(
                MenuCodexTabView(
                    model: model,
                    onDefault: { _ in },
                    onAutoReview: { _ in calls += 1 },
                    onApplyCodex: {}
                ),
                height: MenuCodexTabView.height
            )
            defer { host.close() }
            try await host.activateAccessibility()
            for label in [
                "Previous model for Custom approval review model", "Next model for Custom approval review model",
            ] {
                let button = try host.element(label: label)
                #expect(!button.isAccessibilityEnabled())
                _ = button.accessibilityPerformPress()
            }
            for _ in 0..<20 { await Task.yield() }
            #expect(calls == 0)
            #expect(host.hosting.fittingSize.height == MenuCodexTabView.height)
        }
    }

    private struct Fixture {
        let model: AppModel
        let primary: ModelMapping
        let reviewer: ModelMapping
    }

    private func makeModel() -> Fixture {
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "alpha"), DiscoveredModel(id: "review")]
        )
        let primary = ModelMapping(providerID: provider.id, modelID: "alpha")
        let reviewer = ModelMapping(providerID: provider.id, modelID: "review")
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: AppConfiguration(
                    providers: [provider],
                    codex: CodexConfiguration(connected: true, defaultModel: primary, excludedModels: [reviewer])
                )
            )
        )
        return Fixture(model: model, primary: primary, reviewer: reviewer)
    }
}
