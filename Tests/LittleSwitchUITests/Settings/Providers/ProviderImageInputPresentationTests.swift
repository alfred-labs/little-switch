import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Provider image input presentation")
struct ProviderImageInputPresentationTests {
    private let english = Locale(identifier: "en")

    @Test("Route-specific evidence stays visible after inconclusive revalidation")
    func evidence() throws {
        var provider = Provider(
            name: "Example",
            baseURL: "https://provider.example",
            authMode: .none,
            models: [DiscoveredModel(id: "model")],
            status: .ready)
        let key = try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .chatCompletions)
        provider.imageInputObservations = [
            ModelImageInputObservation(
                key: key, verdict: .unsupported, source: .providerRejection, observedAt: .distantPast)
        ]
        let diagnostic = ModelImageInputProbeDiagnostic(
            key: key,
            result: ModelImageInputProbeResult(
                outcome: .inconclusive(.timeout), usage: nil, startedAt: Date(), durationSeconds: 15))
        let presentation = ProviderModelImageInputPresentation.make(
            provider: provider,
            model: provider.models[0],
            learnedNative: false,
            diagnostics: [diagnostic],
            locale: english)
        #expect(presentation.title == "Images refused")
        #expect(presentation.help.contains("Chat Completions"))
        #expect(presentation.help.contains("Provider rejection"))
        #expect(presentation.help.contains("Usage unavailable"))
        #expect(presentation.help.contains("Check timed out"))
        #expect(provider.status == .ready)
        let native = ProviderModelImageInputPresentation.make(
            provider: provider, model: provider.models[0], learnedNative: true, locale: english)
        #expect(native.title == "Image support unknown")
        provider.imageInputOverride = .enabled
        #expect(
            ProviderModelImageInputPresentation.make(
                provider: provider, model: provider.models[0], learnedNative: false, locale: english
            ).title == "Images forced on")
    }

    @Test("The new progress and one-week cache copy resolve in English and French")
    func localizedCopy() {
        #expect(L10n.imageProbeProgress(completed: 1, total: 4, locale: english) == "Checking image support: 1/4")
        #expect(
            L10n.imageProbeProgress(completed: 1, total: 4, locale: Locale(identifier: "fr"))
                == "Vérification des images : 1/4")
        #expect(
            L10n.string("Checks are cached for 7 days.", locale: Locale(identifier: "fr"))
                == "Les vérifications sont conservées pendant 7 jours.")
    }

    @Test("The provider row shows nonblocking progress without replacing Ready")
    func nativeProgress() async throws {
        let provider = Provider(name: "Example", baseURL: "https://provider.example", authMode: .none, status: .ready)
        let host = MenuControlTestHost(
            ProviderSettingsRow(
                provider: provider,
                scriptFailure: nil,
                imageProgress: ProviderImageProbeProgress(completed: 1, total: 4, running: true)),
            width: 640,
            height: 120)
        defer { host.close() }
        try await host.activateAccessibility()
        let text = host.textContent.joined(separator: " ")
        #expect(text.contains(L10n.imageProbeProgress(completed: 1, total: 4)))
        #expect(text.contains(L10n.string("Ready")))
    }

    @Test("New credentials or endpoint edits cannot display old verification as current")
    func draftEvidenceIdentity() throws {
        var provider = Provider(
            name: "Example",
            baseURL: "https://provider.example",
            authMode: .none,
            models: [DiscoveredModel(id: "model")])
        provider.imageInputObservations = [
            ModelImageInputObservation(
                key: try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .responses),
                verdict: .verified,
                source: .visualProbe,
                observedAt: Date())
        ]
        var draft = ProviderDraft(provider: provider)
        let verified = ProviderModelImageInputPresentation.forDraft(
            draft, providers: [provider], learnedNative: true, diagnostics: [])
        #expect(verified["model"]?.title == L10n.string("Images verified"))
        draft.credential = "synthetic-new-credential"
        let changedCredential = ProviderModelImageInputPresentation.forDraft(
            draft, providers: [provider], learnedNative: true, diagnostics: [])
        #expect(changedCredential["model"]?.title == L10n.string("Image support unknown"))
        draft.credential = ""
        draft.baseURL = "https://other.example"
        let changedEndpoint = ProviderModelImageInputPresentation.forDraft(
            draft, providers: [provider], learnedNative: true, diagnostics: [])
        #expect(changedEndpoint["model"]?.title == L10n.string("Image support unknown"))
        #expect(draft.modelContexts.count == 1)
    }

    @Test("Polling publishes observations and pending flags without overwriting drafts or navigation")
    func polling() throws {
        let provider = Provider(
            name: "Example",
            baseURL: "https://provider.example",
            authMode: .none,
            models: [DiscoveredModel(id: "model")])
        var snapshot = CoordinatorSnapshot(configuration: AppConfiguration(providers: [provider]))
        let model = AppModel(snapshot: snapshot)
        model.selectedSection = .providers
        model.expandedCodexCatalogProviderIDs = [provider.id]
        model.errorMessage = "Retain this notice"
        model.isBusy = true
        snapshot.configuration.providers[0].imageInputObservations = [
            ModelImageInputObservation(
                key: try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .responses),
                verdict: .verified,
                source: .visualProbe,
                observedAt: Date())
        ]
        snapshot.monitoringSnapshotSequence = 2
        snapshot.hasPendingCodexChanges = true
        snapshot.imageProbeProgress[provider.id] = .init(completed: 1, total: 1, running: false)
        GatewayActivityPollingUpdate(snapshot: snapshot, activity: .starting).apply(to: model)
        #expect(model.providers[0].imageInputObservations == snapshot.configuration.providers[0].imageInputObservations)
        #expect(model.hasPendingCodexChanges)
        #expect(model.imageInputState.progress == snapshot.imageProbeProgress)
        #expect(model.selectedSection == .providers)
        #expect(model.expandedCodexCatalogProviderIDs == [provider.id])
        #expect(model.errorMessage == "Retain this notice")
        #expect(model.isBusy)
        snapshot.monitoringSnapshotSequence = 1
        snapshot.configuration.providers[0].imageInputObservations = []
        GatewayActivityPollingUpdate(snapshot: snapshot, activity: .starting).apply(to: model)
        #expect(model.providers[0].imageInputObservations.count == 1)
    }
}
