import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Codex catalog image observations")
struct CodexCatalogImageObservationTests {
    @Test("Mixed models and the hidden reviewer follow the actual selected wire")
    func routeScopedCatalog() throws {
        let provider = try Self.provider()
        let configuration = CodexConfiguration(
            defaultModel: ModelMapping(providerID: provider.id, modelID: "text"))
        let native = try CodexCatalog.make(
            providers: [provider], configuration: configuration, responsesWireVerdicts: [provider.id: true])
        let adapted = try CodexCatalog.make(
            providers: [provider], configuration: configuration, responsesWireVerdicts: [provider.id: false])
        #expect(native.models.map(\.inputModalities) == [["text", "image"], ["text", "image"], ["text", "image"]])
        #expect(adapted.models.map(\.inputModalities) == [["text"], ["text", "image"], ["text"]])
        var expected = native
        expected.models[0].inputModalities = ["text"]
        expected.models[2].inputModalities = ["text"]
        #expect(adapted == expected)
        let signature = try CodexManagedProfileSignature.resolve(
            providers: [provider], configuration: configuration, responsesWireVerdicts: [provider.id: false])
        #expect(
            try signature.catalogData
                == CodexCatalog.encode(
                    providers: [provider], configuration: configuration, responsesWireVerdicts: [provider.id: false]))
    }

    @Test("OpenCode consumes the same route-specific observations")
    func openCode() throws {
        let provider = try Self.provider()
        let adapted = try OpenCodeManagedSettings.resolve(
            providers: [provider],
            codex: .disconnected,
            configuration: .disconnected,
            responsesWireVerdicts: [provider.id: false])
        let native = try OpenCodeManagedSettings.resolve(
            providers: [provider],
            codex: .disconnected,
            configuration: .disconnected,
            responsesWireVerdicts: [provider.id: true])
        #expect(adapted.provider.models["example:text"]?.modalities?.input == ["text"])
        #expect(native.provider.models["example:text"]?.modalities?.input == ["text", "image"])
        #expect(adapted.provider.models["example:vision"]?.modalities?.input == ["text", "image"])
    }

    static func provider() throws -> Provider {
        var provider = Provider(
            name: "Example",
            baseURL: "https://provider.example",
            authMode: .none,
            models: [DiscoveredModel(id: "text"), DiscoveredModel(id: "vision")])
        provider.imageInputObservations = try [
            ModelImageInputObservation(
                key: ModelImageInputPolicyResolver.key(provider: provider, modelID: "text", wire: .chatCompletions),
                verdict: .unsupported,
                source: .providerRejection,
                observedAt: .distantPast),
            ModelImageInputObservation(
                key: ModelImageInputPolicyResolver.key(provider: provider, modelID: "vision", wire: .responses),
                verdict: .verified,
                source: .visualProbe,
                observedAt: .distantPast),
        ]
        return provider
    }
}
