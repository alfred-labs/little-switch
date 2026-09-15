import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Model image input policy")
struct ModelImageInputPolicyTests {
    private let model = DiscoveredModel(id: "model")

    @Test("An observation applies only to its exact provider, model, wire and endpoint")
    func routeScopedObservation() throws {
        let provider = Provider(name: "Example", baseURL: "https://provider.example", authMode: .none)
        let rejection = ModelImageInputObservation(
            key: try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .chatCompletions),
            verdict: .unsupported,
            source: .providerRejection,
            observedAt: Date(timeIntervalSince1970: 1))
        #expect(try !accepts(provider, model, .chatCompletions, [rejection]))
        #expect(try accepts(provider, model, .responses, [rejection]))
        #expect(try accepts(provider, DiscoveredModel(id: "other"), .chatCompletions, [rejection]))
        var changed = provider
        changed.baseURL = "https://different.example"
        #expect(try accepts(changed, model, .chatCompletions, [rejection]))
        changed = provider
        changed.id = UUID()
        #expect(try accepts(changed, model, .chatCompletions, [rejection]))
    }

    @Test("User overrides beat observations, which beat advertised metadata")
    func policyPrecedence() throws {
        var provider = Provider(name: "Example", baseURL: "https://provider.example", authMode: .none)
        let key = try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .responses)
        let rejection = ModelImageInputObservation(
            key: key, verdict: .unsupported, source: .providerRejection, observedAt: Date(timeIntervalSince1970: 1))
        let verified = ModelImageInputObservation(
            key: key, verdict: .verified, source: .visualProbe, observedAt: Date(timeIntervalSince1970: 2))
        let advertised = DiscoveredModel(id: "model", supportsImageInput: true)
        #expect(try !accepts(provider, advertised, .responses, [rejection]))
        #expect(try accepts(provider, model, .responses, [verified, rejection]))
        provider.imageInputOverride = .enabled
        #expect(try accepts(provider, model, .responses, [rejection]))
        provider.imageInputOverride = .disabled
        #expect(try !accepts(provider, model, .responses, [verified]))
        provider.imageInputOverride = nil
        #expect(try !accepts(provider, DiscoveredModel(id: "model", supportsImageInput: false), .responses, []))
        #expect(try accepts(provider, advertised, .responses, []))
        #expect(try accepts(provider, model, .responses, []))
    }

    @Test("The key uses the same normalized split endpoint as production")
    func forwardingEndpoint() throws {
        var provider = Provider(name: "Example", baseURL: "https://provider.example/api/", authMode: .none)
        #expect(
            try ModelImageInputPolicyResolver.key(provider: provider, modelID: "Exact-ID", wire: .responses)
                == ModelImageInputKey(
                    providerID: provider.id,
                    modelID: "Exact-ID",
                    wire: .responses,
                    endpoint: "https://provider.example/api/v1/responses"))
        provider.anthropicBaseURL = "https://provider.example/anthropic"
        #expect(
            try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .chatCompletions).endpoint
                == "https://provider.example/api/chat/completions")
        provider.baseURL = "not a URL"
        #expect(throws: ProviderEndpoint.Error.self) {
            try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .responses)
        }
    }

    @Test("Route resolution prioritizes explicit choice, learned route, save-time absence, then native")
    func wirePrecedence() {
        var provider = Provider(name: "Example", baseURL: "https://provider.example", authMode: .none)
        #expect(ProviderResponsesWireResolver.resolve(provider: provider, learnedNative: nil) == .responses)
        provider.wireProbe = ProviderWireProbe(messages: .unknown, responses: .absent, chatCompletions: .available)
        #expect(ProviderResponsesWireResolver.resolve(provider: provider, learnedNative: nil) == .chatCompletions)
        #expect(ProviderResponsesWireResolver.resolve(provider: provider, learnedNative: true) == .responses)
        #expect(ProviderResponsesWireResolver.resolve(provider: provider, learnedNative: false) == .chatCompletions)
        provider.responsesWireOverride = .native
        #expect(ProviderResponsesWireResolver.resolve(provider: provider, learnedNative: false) == .responses)
        provider.responsesWireOverride = .chatCompletions
        #expect(ProviderResponsesWireResolver.resolve(provider: provider, learnedNative: true) == .chatCompletions)
    }

    private func accepts(
        _ provider: Provider,
        _ model: DiscoveredModel,
        _ wire: ModelImageInputWire,
        _ observations: [ModelImageInputObservation]
    ) throws -> Bool {
        try ModelImageInputPolicyResolver.acceptsImages(
            provider: provider, model: model, wire: wire, observations: observations)
    }
}
