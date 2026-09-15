import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Image probe scheduling")
struct ModelImageProbeScheduleTests {
    @Test("The one-week boundary preserves stale facts and honors metadata and overrides")
    func expiry() throws {
        var provider = imageProbeProvider()
        let model = provider.models[0]
        let key = try ModelImageInputPolicyResolver.key(provider: provider, modelID: model.id, wire: .responses)
        let observed = ModelImageInputObservation(
            key: key, verdict: .unsupported, source: .visualProbe, observedAt: Date(timeIntervalSince1970: 0))
        #expect(ModelImageProbeSchedule.observationTTL == 604_800)
        #expect(try candidates(provider, [observed], at: 604_799).isEmpty)
        #expect(try candidates(provider, [observed], at: 604_800) == [model])
        #expect(
            try !ModelImageInputPolicyResolver.acceptsImages(
                provider: provider, model: model, wire: .responses, observations: [observed]))
        provider.models[0].supportsImageInput = false
        #expect(try candidates(provider, [observed], at: 604_800).isEmpty)
        provider.models[0].supportsImageInput = true
        #expect(try candidates(provider, [observed], at: 604_800).count == 1)
        provider.imageInputOverride = .enabled
        #expect(try candidates(provider, [observed], at: 604_800).isEmpty)
    }

    @Test("Four candidates prioritize the preferred IDs then stable catalog order")
    func budget() throws {
        let provider = imageProbeProvider(models: ["z", "d", "b", "c", "a", "preferred"])
        let candidates = try ModelImageProbeSchedule.candidates(
            provider: provider,
            preferredModelIDs: ["preferred"],
            wire: .responses,
            observations: [],
            now: Date(),
            limit: 4)
        #expect(candidates.map(\.id) == ["preferred", "a", "b", "c"])
        #expect(
            try ModelImageProbeSchedule.candidates(
                provider: provider,
                preferredModelIDs: [],
                wire: .responses,
                observations: [],
                now: Date(),
                limit: 0
            ).isEmpty)
    }

    private func candidates(
        _ provider: Provider, _ observations: [ModelImageInputObservation], at seconds: TimeInterval
    ) throws -> [DiscoveredModel] {
        try ModelImageProbeSchedule.candidates(
            provider: provider,
            preferredModelIDs: [],
            wire: .responses,
            observations: observations,
            now: Date(timeIntervalSince1970: seconds),
            limit: 4)
    }
}

func imageProbeProvider(models: [String] = ["model"]) -> Provider {
    Provider(
        name: "Example",
        baseURL: "https://provider.example",
        authMode: .none,
        models: models.map { DiscoveredModel(id: $0) },
        status: .ready,
        maximumParallelRequests: 1)
}
