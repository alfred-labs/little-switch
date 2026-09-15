import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Draft image input presentation")
struct ProviderDraftImageInputPresentationTests {
    @Test("An unsaved provider derives its model rows without inheriting a learned route")
    func newProvider() {
        var draft = ProviderDraft()
        draft.name = "New"
        draft.baseURL = "https://provider.example"
        draft.modelContexts = ["one", "two"].map { ModelContextDraft(model: DiscoveredModel(id: $0)) }
        let presentations = ProviderModelImageInputPresentation.forDraft(
            draft, providers: [], learnedNative: false, diagnostics: [])
        #expect(Set(presentations.keys) == ["one", "two"])
        for presentation in presentations.values {
            #expect(presentation.title == L10n.string("Image support unknown"))
            #expect(presentation.help.hasPrefix("Responses\n"))
        }
    }

    @Test("A duplicated provider keeps its model rows but cannot inherit the source verification")
    func duplicatedProvider() throws {
        var source = Provider(
            name: "Source",
            baseURL: "https://provider.example",
            authMode: .none,
            models: [DiscoveredModel(id: "model")])
        source.imageInputObservations = [
            ModelImageInputObservation(
                key: try ModelImageInputPolicyResolver.key(provider: source, modelID: "model", wire: .responses),
                verdict: .verified,
                source: .visualProbe,
                observedAt: Date())
        ]
        let draft = ProviderDraft(duplicating: source, providers: [source])
        let presentations = ProviderModelImageInputPresentation.forDraft(
            draft, providers: [source], learnedNative: true, diagnostics: [])
        #expect(Set(presentations.keys) == ["model"])
        #expect(presentations["model"]?.title == L10n.string("Image support unknown"))
    }
}
