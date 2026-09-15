import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Provider image input details")
struct ProviderImageInputDetailsTests {
    private let english = Locale(identifier: "en")

    @Test("Catalog metadata is described as advertised support", arguments: [true, false])
    func metadata(supported: Bool) {
        let model = DiscoveredModel(id: "model", supportsImageInput: supported)
        let provider = Provider(name: "Example", baseURL: "https://provider.example", authMode: .none, models: [model])
        let presentation = ProviderModelImageInputPresentation.make(
            provider: provider, model: model, learnedNative: false, locale: english)
        #expect(presentation.title == (supported ? "Images advertised" : "Text only advertised"))
        #expect(presentation.help.contains("Provider metadata"))
        #expect(presentation.help.contains("Chat Completions"))
    }

    @Test("The latest evidence and diagnostic win independently of their array order")
    func newestDetails() throws {
        var provider = Provider(
            name: "Example",
            baseURL: "https://provider.example",
            authMode: .none,
            models: [DiscoveredModel(id: "model")])
        let key = try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .responses)
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        provider.imageInputObservations = [
            ModelImageInputObservation(key: key, verdict: .unsupported, source: .visualProbe, observedAt: newer),
            ModelImageInputObservation(key: key, verdict: .verified, source: .visualProbe, observedAt: older),
        ]
        let diagnostics = [
            ModelImageInputProbeDiagnostic(
                key: key,
                result: ModelImageInputProbeResult(
                    outcome: .inconclusive(.wrongAnswer),
                    usage: ResponsesUsage(inputTokens: 187, outputTokens: 63),
                    startedAt: newer,
                    durationSeconds: 1.25)),
            ModelImageInputProbeDiagnostic(
                key: key,
                result: ModelImageInputProbeResult(
                    outcome: .inconclusive(.timeout),
                    usage: nil,
                    startedAt: older,
                    durationSeconds: 15)),
        ]
        let presentation = ProviderModelImageInputPresentation.make(
            provider: provider,
            model: provider.models[0],
            learnedNative: true,
            diagnostics: diagnostics,
            locale: english)
        #expect(presentation.title == "Images refused")
        #expect(presentation.help.contains("Visual check"))
        #expect(presentation.help.contains("The visual answer did not match"))
        #expect(presentation.help.contains("Duration: 1.25 s"))
        #expect(presentation.help.contains("Input: 187, output: 63, total: 250 tokens"))
        #expect(!presentation.help.contains("Check timed out"))
        #expect(!presentation.help.contains("Usage unavailable"))
    }

    @Test(
        "An inconclusive check explains its specific failure",
        arguments: zip(
            [
                ModelImageProbeInconclusiveReason.wrongAnswer, .incompleteResponse, .invalidResponse,
                .routeUnavailable, .transport, .timeout, .sizeLimit, .httpStatus(429),
            ],
            [
                "The visual answer did not match", "The check returned an incomplete answer",
                "The check returned an unreadable answer", "The model route was unavailable",
                "The check could not reach the provider", "Check timed out",
                "The check exceeded its size limit", "The check returned HTTP 429",
            ]))
    func failureReason(reason: ModelImageProbeInconclusiveReason, detail: String) throws {
        let model = DiscoveredModel(id: "model")
        let provider = Provider(name: "Example", baseURL: "https://provider.example", authMode: .none, models: [model])
        let diagnostic = ModelImageInputProbeDiagnostic(
            key: try ModelImageInputPolicyResolver.key(provider: provider, modelID: model.id, wire: .responses),
            result: ModelImageInputProbeResult(
                outcome: .inconclusive(reason), usage: nil, startedAt: .distantPast, durationSeconds: 0))
        let presentation = ProviderModelImageInputPresentation.make(
            provider: provider, model: model, learnedNative: true, diagnostics: [diagnostic], locale: english)
        #expect(presentation.title == "Check inconclusive")
        #expect(presentation.help.contains(detail))
    }
}
