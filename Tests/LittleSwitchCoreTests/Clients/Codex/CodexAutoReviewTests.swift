import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex automatic approval review")
struct CodexAutoReviewTests {
    @Test("A separately configured reviewer routes independently of the task default and exposure")
    func configuredReviewer() throws {
        var snapshot = makeSnapshot()
        let provider = try #require(snapshot.providers.first)
        let reviewer = ModelMapping(providerID: provider.id, modelID: "small")
        snapshot.codex = try JSONDecoder().decode(
            CodexConfiguration.self,
            from: JSONSerialization.data(withJSONObject: [
                "connected": false,
                "defaultModel": ["providerID": provider.id.uuidString, "modelID": "xlarge"],
                "autoReviewModel": ["providerID": provider.id.uuidString, "modelID": "small"],
                "excludedModels": [["providerID": provider.id.uuidString, "modelID": "small"]],
            ]))

        #expect(snapshot.resolveCodex(model: "codex-auto-review")?.mapping == reviewer)
        #expect(snapshot.resolveCodex(model: "example/small") == nil)
        let catalog = try CodexCatalog.make(providers: snapshot.providers, configuration: snapshot.codex)
        #expect(catalog.models.last?.contextWindow == 128_000)
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.codex)) as? [String: Any]
        #expect(
            saved?["autoReviewModel"] as? [String: String]
                == ["providerID": provider.id.uuidString, "modelID": "small"])

        snapshot.providers[0].models.removeAll { $0.id == "small" }
        #expect(snapshot.resolveCodex(model: "codex-auto-review") == nil)
        #expect(throws: CodexCatalog.Error.unavailableAutoReviewModel) {
            try CodexCatalog.make(providers: snapshot.providers, configuration: snapshot.codex)
        }
    }

    @Test("Reviewer changes alter the managed profile even when model capabilities match")
    func reviewerSignature() throws {
        var snapshot = makeSnapshot()
        let provider = Provider(
            name: "Reviewer",
            baseURL: "https://review.example.com",
            authMode: .none,
            models: [DiscoveredModel(id: "reviewer", contextWindowOverride: 202_752)])
        snapshot.providers.append(provider)
        let before = try CodexManagedProfileSignature.resolve(
            providers: snapshot.providers, configuration: snapshot.codex)
        let mapping = ModelMapping(providerID: provider.id, modelID: "reviewer")
        snapshot.codex.autoReviewModel = mapping
        let after = try CodexManagedProfileSignature.resolve(
            providers: snapshot.providers, configuration: snapshot.codex)

        #expect(before.modelSlug == after.modelSlug)
        #expect(before.catalogData != after.catalogData)
        #expect(snapshot.resolveCodex(model: "codex-auto-review")?.mapping == mapping)
        snapshot.codex.defaultModel = ModelMapping(providerID: snapshot.providers[0].id, modelID: "small")
        #expect(snapshot.resolveCodex(model: "codex-auto-review")?.mapping == mapping)
        #expect(
            snapshot.providerRequestPoolConfiguration(providerRevisions: [:]).routes[
                ProviderRequestRouteKey(client: .codex, modelIdentifier: "codex-auto-review")]
                == ProviderRequestRouteTarget(providerID: provider.id, modelID: "reviewer"))
    }

    @Test("The flat reviewer alias resolves to the exposed Codex default")
    func defaultRouting() throws {
        let snapshot = makeSnapshot()
        let target = try #require(snapshot.resolveCodex(model: "example/xlarge"))

        #expect(snapshot.resolveCodex(model: "codex-auto-review") == target)
        #expect(
            snapshot.validCodexTargets == [
                "example/small": CodexModelTarget(
                    provider: target.provider, model: DiscoveredModel(id: "small")),
                "example/xlarge": target,
                "codex-auto-review": target,
            ])
        #expect(snapshot.resolveCodex(model: "Codex-auto-review") == nil)
        #expect(snapshot.resolveCodex(model: "codex-auto-review[1m]") == nil)
        #expect(snapshot.resolve(model: "codex-auto-review") == nil)
    }

    @Test("The reviewer uses the same normalized default and respects exclusions")
    func defaultNormalization() throws {
        var snapshot = makeSnapshot()
        let defaultMapping = try #require(snapshot.codex.defaultModel)
        snapshot.codex.excludedModels = [defaultMapping]
        let fallback = snapshot.resolveCodex(model: "example/small")

        #expect(fallback != nil)
        #expect(snapshot.resolveCodex(model: "codex-auto-review") == fallback)

        snapshot.codex.defaultModel = nil
        #expect(snapshot.resolveCodex(model: "codex-auto-review") == fallback)

        snapshot.codex.excludedModels.append(
            ModelMapping(providerID: defaultMapping.providerID, modelID: "small"))
        #expect(snapshot.resolveCodex(model: "codex-auto-review") == nil)
        #expect(snapshot.validCodexTargets.isEmpty)

        snapshot.providers = []
        #expect(snapshot.resolveCodex(model: "codex-auto-review") == nil)
    }

    @Test("The reviewer enters the existing provider pool without a new capacity bucket")
    func poolRouting() throws {
        let snapshot = makeSnapshot()
        let provider = try #require(snapshot.providers.first)
        let configuration = snapshot.providerRequestPoolConfiguration(
            providerRevisions: [provider.id: 7])

        #expect(
            configuration
                == ProviderRequestPoolConfiguration(
                    providers: [
                        ProviderRequestPoolProviderConfiguration(
                            id: provider.id,
                            displayName: provider.name,
                            maximumParallelRequests: provider.maximumParallelRequests,
                            revision: 7)
                    ],
                    routes: [
                        ProviderRequestRouteKey(client: .codex, modelIdentifier: "example/small"):
                            ProviderRequestRouteTarget(providerID: provider.id, modelID: "small"),
                        ProviderRequestRouteKey(client: .codex, modelIdentifier: "example/xlarge"):
                            ProviderRequestRouteTarget(providerID: provider.id, modelID: "xlarge"),
                        ProviderRequestRouteKey(client: .codex, modelIdentifier: "codex-auto-review"):
                            ProviderRequestRouteTarget(providerID: provider.id, modelID: "xlarge"),
                    ]))
    }

    @Test("The managed catalog advertises a hidden reviewer with the default's capabilities")
    func catalogMetadata() throws {
        let snapshot = makeSnapshot()
        let catalog = try CodexCatalog.make(
            providers: snapshot.providers, configuration: snapshot.codex)
        var expected = try #require(catalog.models.first)
        expected.slug = "codex-auto-review"
        expected.displayName = "codex-auto-review"
        expected.description = "Approval reviews via Example/xlarge"
        expected.visibility = "hide"
        expected.priority = 2

        #expect(catalog.models.last == expected)
        #expect(catalog.models.map(\.slug) == ["example/xlarge", "example/small", "codex-auto-review"])
        #expect(catalog.models.filter { $0.visibility == "list" }.count == 2)
        for model in catalog.models {
            #expect(snapshot.resolveCodex(model: model.slug) != nil)
        }

        let encoded = try CodexCatalog.encode(
            providers: snapshot.providers, configuration: snapshot.codex)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let models = try #require(object["models"] as? [[String: Any]])
        #expect(
            models.compactMap { $0["auto_review_model_override"] as? String }
                == ["codex-auto-review", "codex-auto-review", "codex-auto-review"])
    }

    func makeSnapshot() -> RoutingSnapshot {
        let provider = Provider(
            name: "Example",
            baseURL: "https://example.com",
            authMode: .none,
            models: [
                DiscoveredModel(id: "small"),
                DiscoveredModel(id: "xlarge", contextWindowOverride: 202_752),
            ])
        return RoutingSnapshot(
            generation: 1,
            providers: [provider],
            mappings: [:],
            codex: CodexConfiguration(
                defaultModel: ModelMapping(providerID: provider.id, modelID: "xlarge")))
    }
}
