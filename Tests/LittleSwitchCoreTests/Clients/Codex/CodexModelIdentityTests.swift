import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Managed model identities")
struct CodexModelIdentityTests {
    @Test("Case, component separators and literal escapes stay distinct")
    func injectiveSlugs() throws {
        let cases = [
            ("A", "B/C"), ("A/B", "C"), ("A", "Model"), ("A", "model"),
            ("A", "%4dodel"), ("A%2fB", "C"), ("A", "é"), ("A", "e\u{301}"),
            ("A", "b:c"), ("A:b", "c"),
        ]
        let slugs = cases.map { name, model in
            CodexCatalog.slug(for: target(provider: name, model: model))
        }
        #expect(Set(slugs.map { $0.lowercased() }).count == cases.count)
        #expect(slugs.allSatisfy { !$0.contains("/") })
    }

    @Test("Legacy aliases cannot be captured by another model's new encoded identifier")
    func legacyCanonicalSeparation() throws {
        var provider = target(provider: "Local", model: "Model").provider
        provider.models.append(DiscoveredModel(id: "%4dodel"))
        let original = CodexModelTarget(provider: provider, model: provider.models[0])
        let escaped = CodexModelTarget(provider: provider, model: provider.models[1])
        let snapshot = RoutingSnapshot(generation: 0, providers: [provider], mappings: [:])
        #expect(CodexCatalog.slug(for: original) == "local:%4dodel")
        #expect(CodexCatalog.slug(for: escaped) == "local:%254dodel")
        #expect(snapshot.resolveCodex(model: "local/model") == original)
        #expect(snapshot.resolveCodex(model: "local/%4dodel") == escaped)
        #expect(snapshot.resolveCodex(model: "local:%4dodel") == original)
        #expect(snapshot.resolveCodex(model: "local:%254dodel") == escaped)
        let pool = snapshot.providerRequestPoolConfiguration(providerRevisions: [:])
        #expect(
            pool.routes[ProviderRequestRouteKey(client: .codex, modelIdentifier: "local/%4dodel")]?.modelID == "%4dodel"
        )
        #expect(
            pool.routes[ProviderRequestRouteKey(client: .codex, modelIdentifier: "local:%4dodel")]?.modelID == "Model")
    }

    @Test("Catalog and OpenCode keep every case-distinct model")
    func catalogsKeepDistinctModels() throws {
        let target = target(provider: "Local", model: "Model")
        var provider = target.provider
        provider.models.append(DiscoveredModel(id: "model"))
        let catalog = try CodexCatalog.make(providers: [provider], configuration: CodexConfiguration())
        let visible = catalog.models.filter { $0.visibility == "list" }
        #expect(Set(visible.map(\.slug)).count == 2)
        let settings = try OpenCodeManagedSettings.resolve(
            providers: [provider], codex: CodexConfiguration(), configuration: OpenCodeConfiguration())
        #expect(settings.provider.models.count == 2)
        let snapshot = RoutingSnapshot(generation: 0, providers: [provider], mappings: [:])
        for model in provider.models {
            let expected = CodexModelTarget(provider: provider, model: model)
            #expect(snapshot.resolveCodex(model: CodexCatalog.slug(for: expected)) == expected)
        }
    }

    @Test("Legacy aliases remain available only when unambiguous")
    func legacyAliases() {
        let original = target(provider: "A/B", model: "C")
        var snapshot = RoutingSnapshot(generation: 0, providers: [original.provider], mappings: [:])
        #expect(snapshot.resolveCodex(model: "a/b/c") == original)
        let pool = snapshot.providerRequestPoolConfiguration(providerRevisions: [:])
        #expect(pool.routes[ProviderRequestRouteKey(client: .codex, modelIdentifier: "a/b/c")]?.modelID == "C")
        snapshot.providers.append(target(provider: "A", model: "B/C").provider)
        #expect(snapshot.resolveCodex(model: "a/b/c") == nil)
        #expect(snapshot.resolveCodex(model: "unknown") == nil)
    }

    @Test("Invalid repeated identities fail catalog creation without trapping routing")
    func invalidCatalogDoesNotTrap() {
        var provider = target(provider: "Local", model: "same").provider
        provider.models.append(provider.models[0])
        #expect(throws: CodexCatalog.Error.ambiguousModelIdentifiers) {
            try CodexCatalog.make(providers: [provider], configuration: CodexConfiguration())
        }
        #expect(throws: OpenCodeManagedSettings.Error.ambiguousModelIdentifiers) {
            try OpenCodeManagedSettings.resolve(
                providers: [provider], codex: CodexConfiguration(), configuration: OpenCodeConfiguration())
        }
        let snapshot = RoutingSnapshot(generation: 0, providers: [provider], mappings: [:])
        #expect(snapshot.resolveCodex(model: "local/same") == nil)
    }

    private func target(provider name: String, model id: String) -> CodexModelTarget {
        let model = DiscoveredModel(id: id)
        let provider = Provider(name: name, baseURL: "http://127.0.0.1:11434", authMode: .none, models: [model])
        return CodexModelTarget(provider: provider, model: model)
    }
}
