import AppKit
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Model catalog provider toggle", .serialized)
struct ModelCatalogProviderToggleTests {
    @Test("Display names preserve brands and technical identifiers")
    func providerDisplayNames() {
        let names = [
            ("ollama", "Ollama"), ("current provider", "Current provider"),
            ("OpenAI", "OpenAI"), ("z.ai", "z.ai"), ("provider-1", "provider-1"),
            ("", ""), (" leading", " leading"),
        ]
        for (name, expected) in names {
            #expect(ModelCatalogProviderName.title(name) == expected)
        }
    }

    @Test(
        "One native press emits one complete group intent for all, partial, and off states",
        arguments: [[true, true], [true, false], [false, true], [false, false]]
    )
    func pressDispatchesOneGroupIntent(values: [Bool]) async throws {
        let configuration = configuration(values: values)
        let model = AppModel(snapshot: CoordinatorSnapshot(configuration: configuration))
        let recorder = CatalogExposureRecorder()
        let host = MenuControlTestHost(
            ModelCatalogView(model: model, onExposure: recorder.record), width: 600, height: 300
        )
        defer { host.close() }
        try await host.activateAccessibility()
        let control = try host.nativeView(of: NSSwitch.self)
        let toggle = try host.element(label: "Enable all models from Ollama")
        let exposedCount = values.count { $0 }
        #expect(control.state == (values.allSatisfy(\.self) ? .on : .off))
        #expect(toggle.accessibilityValueDescription() == "\(exposedCount) of 2 models enabled")
        #expect(host.textContent.contains("\(exposedCount) of 2"))

        #expect(toggle.accessibilityPerformPress())
        try await recorder.waitForCall()
        host.render()

        #expect(
            recorder.calls == [
                CatalogExposureIntent(
                    mappings: model.codexExposureGroups[0].options.map(\.mapping),
                    exposed: !values.allSatisfy(\.self)
                )
            ])
        #expect(model.configuration == configuration)
    }

    @Test("The current parent snapshot supplies the provider label, mappings, and callback")
    func parentUpdateReplacesSnapshotAndAction() async throws {
        let initial = configuration(values: [false, false])
        let model = AppModel(snapshot: CoordinatorSnapshot(configuration: initial))
        let oldRecorder = CatalogExposureRecorder()
        let newRecorder = CatalogExposureRecorder()
        let host = MenuControlTestHost(
            ModelCatalogView(model: model, onExposure: oldRecorder.record), width: 600, height: 300
        )
        defer { host.close() }
        try await host.activateAccessibility()
        #expect(try host.nativeView(of: NSSwitch.self).state == .off)
        var current = initial
        current.providers[0].name = "current provider"
        current.providers[0].models = [DiscoveredModel(id: "current-model")]
        current.codex.excludedModels = []
        model.apply(CoordinatorSnapshot(configuration: current))
        host.hosting.rootView = ModelCatalogView(model: model, onExposure: newRecorder.record)
        host.render()

        let toggle = try host.element(label: "Enable all models from Current provider")
        #expect(toggle.accessibilityValueDescription() == "1 of 1 models enabled")
        #expect(try host.nativeView(of: NSSwitch.self).state == .on)
        #expect(toggle.accessibilityPerformPress())
        try await newRecorder.waitForCall()
        #expect(oldRecorder.calls.isEmpty)
        #expect(
            newRecorder.calls == [
                CatalogExposureIntent(
                    mappings: [ModelMapping(providerID: current.providers[0].id, modelID: "current-model")],
                    exposed: false
                )
            ])
    }

    @Test("Busy and inherited disabled states prevent group changes and can be cleared")
    func disabledStates() async throws {
        let model = AppModel(snapshot: CoordinatorSnapshot(configuration: configuration(values: [true, false])))
        let recorder = CatalogExposureRecorder()
        func content(disabled: Bool) -> some View {
            ModelCatalogView(model: model, onExposure: recorder.record).disabled(disabled)
        }
        let host = MenuControlTestHost(content(disabled: true), width: 600, height: 300)
        defer { host.close() }
        try await host.activateAccessibility()
        for inherited in [true, false] {
            model.isBusy = !inherited
            host.hosting.rootView = content(disabled: inherited)
            host.render()
            let toggle = try host.element(label: "Enable all models from Ollama")
            #expect(!toggle.isAccessibilityEnabled())
            _ = toggle.accessibilityPerformPress()
            #expect(try host.nativeView(of: NSSwitch.self).state == .off)
        }
        await Task.yield()
        #expect(recorder.calls.isEmpty)

        model.isBusy = false
        host.hosting.rootView = content(disabled: false)
        host.render()
        let toggle = try host.element(label: "Enable all models from Ollama")
        #expect(toggle.isAccessibilityEnabled())
        #expect(toggle.accessibilityPerformPress())
        try await recorder.waitForCall()
        #expect(
            recorder.calls == [
                CatalogExposureIntent(mappings: model.modelOptions.map(\.mapping), exposed: true)
            ])
    }

    @Test("A provider containing only the default model cannot be hidden")
    func defaultOnlyProviderIsDisabled() async throws {
        var configuration = configuration(values: [true])
        configuration.codex.defaultModel = ModelMapping(
            providerID: configuration.providers[0].id, modelID: "model-0"
        )
        let model = AppModel(snapshot: CoordinatorSnapshot(configuration: configuration))
        let recorder = CatalogExposureRecorder()
        let host = MenuControlTestHost(
            ModelCatalogView(model: model, onExposure: recorder.record), width: 600, height: 300
        )
        defer { host.close() }
        try await host.activateAccessibility()
        let toggle = try host.element(label: "Enable all models from Ollama")
        #expect(!toggle.isAccessibilityEnabled())
        _ = toggle.accessibilityPerformPress()
        #expect(try host.nativeView(of: NSSwitch.self).state == .on)
        await Task.yield()
        #expect(recorder.calls.isEmpty)
    }

    @Test("An empty provider offers no group toggle")
    func emptyProvider() async throws {
        let model = AppModel(snapshot: CoordinatorSnapshot(configuration: configuration(values: [])))
        let recorder = CatalogExposureRecorder()
        let host = MenuControlTestHost(
            ModelCatalogView(model: model, onExposure: recorder.record), width: 600, height: 300
        )
        defer { host.close() }
        try await host.activateAccessibility()
        #expect(!host.accessibilityElements.contains { $0.accessibilityLabel() == "Enable all models from Ollama" })
        #expect(recorder.calls.isEmpty)
    }

    private func configuration(values: [Bool]) -> AppConfiguration {
        let providerID = UUID()
        let models = values.indices.map { DiscoveredModel(id: "model-\($0)") }
        let excluded = values.indices.filter { !values[$0] }.map {
            ModelMapping(providerID: providerID, modelID: models[$0].id)
        }
        return AppConfiguration(
            providers: [
                Provider(
                    id: providerID,
                    name: "ollama",
                    baseURL: "http://localhost:11434",
                    authMode: .none,
                    models: models
                )
            ],
            codex: CodexConfiguration(excludedModels: excluded)
        )
    }
}

private struct CatalogExposureIntent: Equatable {
    let mappings: [ModelMapping]
    let exposed: Bool
}

@MainActor
private final class CatalogExposureRecorder {
    var calls: [CatalogExposureIntent] = []

    func record(_ mappings: [ModelMapping], _ exposed: Bool) async {
        calls.append(CatalogExposureIntent(mappings: mappings, exposed: exposed))
    }

    func waitForCall() async throws {
        _ = try await eventually(description: "the provider exposure callback") {
            await MainActor.run { self.calls.isEmpty ? nil : true }
        }
    }
}
