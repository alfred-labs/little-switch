import Foundation
import Testing

@testable import LittleSwitchCore

extension DomainTests {
    @Test("Codex slugs resolve only exposed discovered models")
    func resolvesCodexModels() throws {
        let providerID = UUID()
        let visible = ModelMapping(providerID: providerID, modelID: "visible")
        let hidden = ModelMapping(providerID: providerID, modelID: "hidden")
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "visible"), DiscoveredModel(id: "hidden")]
        )
        let snapshot = RoutingSnapshot(
            generation: 1,
            providers: [provider],
            mappings: [:],
            codex: CodexConfiguration(
                defaultModel: visible,
                excludedModels: [hidden]
            )
        )

        let target = try #require(
            snapshot.resolveCodex(model: CodexCatalog.slug(for: visible, in: [provider]))
        )
        #expect(target.mapping == visible)
        #expect(target.provider == provider)
        #expect(snapshot.resolveCodex(model: CodexCatalog.slug(for: hidden, in: [provider])) == nil)
        #expect(snapshot.resolveCodex(model: "unknown") == nil)
    }
}
