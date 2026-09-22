import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

extension CodexAutoReviewTests {
    @Test("Custom reviewer selection leaves native review models and overrides intact", arguments: [false, true])
    func nativeReviewerIsolation(explicitReviewer: Bool) throws {
        var snapshot = makeSnapshot()
        if explicitReviewer {
            snapshot.codex.autoReviewModel = ModelMapping(providerID: snapshot.providers[0].id, modelID: "small")
        }
        let nativeModels: [[String: Any]] = [
            ["slug": "gpt-native", "display_name": "Native", "priority": 10],
            ["slug": "gpt-special", "auto_review_model_override": "openai-special-review", "priority": 20],
            [
                "slug": "codex-auto-review", "display_name": "Native reviewer", "visibility": "hide",
                "context_window": 128_000, "unknown_future": ["preserved": true], "priority": 30,
            ],
        ]
        let encoded = try CodexCatalog.encode(
            providers: snapshot.providers,
            configuration: snapshot.codex,
            nativeCatalogData: JSONSerialization.data(withJSONObject: ["models": nativeModels])
        )
        let root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let models = try #require(root["models"] as? [[String: Any]])
        #expect(
            models.compactMap { $0["slug"] as? String } == [
                "example:xlarge", "example:small", "gpt-native", "gpt-special", "codex-auto-review",
                "little-switch-auto-review",
            ])
        for (index, native) in nativeModels.enumerated() {
            let actual = try #require(models.first { $0["slug"] as? String == native["slug"] as? String })
            var expected = native
            expected["priority"] = index + 2
            expected["supported_in_api"] = false
            #expect(actual as NSDictionary == expected as NSDictionary)
        }
        for model in models where model["supported_in_api"] as? Bool == true {
            #expect(model["auto_review_model_override"] as? String == "little-switch-auto-review")
        }
        let reviewer = try #require(models.last)
        #expect(reviewer["visibility"] as? String == "hide")
        #expect(reviewer["context_window"] as? Int == (explicitReviewer ? 128_000 : 202_752))
    }

    @Test("The managed reviewer alias never captures Codex's native reviewer")
    func separateReviewerRoutes() throws {
        var snapshot = makeSnapshot()
        for modelID in ["xlarge", "small"] {
            let mapping = ModelMapping(providerID: snapshot.providers[0].id, modelID: modelID)
            snapshot.codex.autoReviewModel = mapping
            #expect(snapshot.resolveCodex(model: "little-switch-auto-review")?.mapping == mapping)
            #expect(snapshot.resolveCodex(model: "codex-auto-review") == nil)
            #expect(
                snapshot.providerRequestPoolConfiguration(providerRevisions: [:]).routes[
                    ProviderRequestRouteKey(client: .codex, modelIdentifier: "codex-auto-review")] == nil)
        }
    }
}
