import Foundation
import Testing

@testable import LittleSwitchCore

extension CodexProfileTests {
    @Test("A catalog using the former shared reviewer alias requires Apply", arguments: [false, true])
    func sharedReviewerAliasNeedsApply(withNativeModels: Bool) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        if withNativeModels {
            try Data(
                #"{"models":[{"slug":"gpt-native"},{"slug":"codex-auto-review","display_name":"OpenAI reviewer","visibility":"hide"}]}"#
                    .utf8
            ).write(to: fixture.paths.config.deletingLastPathComponent().appending(path: "models_cache.json"))
        }
        var configuration = fixture.configuration
        configuration.autoReviewModel = configuration.resolvedDefaultModel(in: fixture.providers)
        try fixture.manager.activate(providers: fixture.providers, configuration: configuration)
        let currentCatalog = try String(contentsOf: fixture.paths.catalog, encoding: .utf8)
        var root = try #require(JSONSerialization.jsonObject(with: Data(currentCatalog.utf8)) as? [String: Any])
        var entries = try #require(root["models"] as? [[String: Any]]).filter {
            $0["slug"] as? String != "codex-auto-review"
        }
        for index in entries.indices { entries[index]["priority"] = index }
        root["models"] = entries
        let previousData = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let previousCatalog = (try #require(String(data: previousData, encoding: .utf8)) + "\n").replacingOccurrences(
            of: "little-switch-auto-review", with: "codex-auto-review")
        #expect(currentCatalog != previousCatalog)
        try Data(previousCatalog.utf8).write(to: fixture.paths.catalog)

        #expect(try !fixture.manager.isActive(providers: fixture.providers, configuration: configuration))
        let expected = try CodexManagedProfileSignature.resolve(
            providers: fixture.providers, configuration: configuration)
        guard case .requiresUpdate(let applied) = try fixture.manager.status(expected: expected) else {
            Issue.record("The previous catalog must stay connected with a pending update")
            return
        }
        #expect(applied == (try expected.withLegacyAutoReview()))

        try fixture.manager.activate(providers: fixture.providers, configuration: configuration)
        #expect(try fixture.manager.isActive(providers: fixture.providers, configuration: configuration))
        #expect(try String(contentsOf: fixture.paths.catalog, encoding: .utf8) == currentCatalog)

        try fixture.manager.activate(providers: fixture.providers, configuration: configuration, signature: applied)
        #expect(try String(contentsOf: fixture.paths.catalog, encoding: .utf8) == previousCatalog)
        #expect(try fixture.manager.status(expected: expected) == .requiresUpdate(applied))
    }
}
