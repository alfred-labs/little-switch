import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Codex historical identifier boundaries")
struct CodexLegacyIdentifierBoundaryTests {
    @Test("Ambiguous historical aliases cannot become migration candidates", arguments: [false, true])
    func ambiguousIdentifiers(identical: Bool) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let expected = try CodexManagedProfileSignature.resolve(
            providers: fixture.providers, configuration: fixture.configuration)
        var providers = fixture.providers
        providers[0].models.append(DiscoveredModel(id: identical ? "qwen" : "Qwen"))

        #expect(
            try expected.withLegacyModelIdentifiers(providers: providers, configuration: fixture.configuration) == nil)
    }

    @Test(
        "Unknown defaults and incomplete catalogs cannot establish a historical signature",
        arguments: [
            ("local:other", #"{"models":[]}"#),
            ("local:qwen", #"{}"#),
            ("local:qwen", #"{"models":[]}"#),
            ("local:qwen", #"{"models":[{"slug":"local:qwen","supported_in_api":false}]}"#),
        ]
    )
    func incompleteSignatures(modelSlug: String, catalog: String) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        #expect(
            try CodexProfileLegacyIdentifiers.resolve(
                modelSlug: modelSlug,
                catalogData: Data(catalog.utf8),
                providers: fixture.providers,
                configuration: fixture.configuration) == nil)
    }

    @Test("Native catalog collisions and opaque fields survive migration and rollback")
    func nativeCatalogPreservation() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let native = Data(
            #"""
            {"models":[
              {"slug":"local:qwen","display_name":"New namespace native"},
              {"slug":"local/qwen","display_name":"Former namespace native"},
              {"slug":"native","base_instructions":"Do not rewrite local:qwen or local/qwen"}
            ]}
            """#.utf8)
        try native.write(to: fixture.paths.config.deletingLastPathComponent().appending(path: "models_cache.json"))
        let expected = try CodexManagedProfileSignature.resolve(
            providers: fixture.providers, configuration: fixture.configuration)
        try fixture.manager.activate(providers: fixture.providers, configuration: fixture.configuration)
        let current = try snapshots(fixture)
        let config = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        try Data(config.replacingOccurrences(of: "local:qwen", with: "local/qwen").utf8).write(to: fixture.paths.config)

        var root = try #require(JSONSerialization.jsonObject(with: expected.catalogData) as? [String: Any])
        var managed = try #require(root["models"] as? [[String: Any]])
        managed[0]["slug"] = "local/qwen"
        root["models"] = managed
        let historicalManaged = try JSONSerialization.data(withJSONObject: root)
        let historicalCatalog = try CodexCatalog.mergedData(managedData: historicalManaged, nativeCatalogData: native)
        try historicalCatalog.write(to: fixture.paths.catalog)
        let historical = try snapshots(fixture)

        guard
            case .requiresUpdate(let applied) = try fixture.manager.status(
                providers: fixture.providers, configuration: fixture.configuration, expected: expected)
        else {
            Issue.record("Only managed identifiers change; native catalog snapshots must remain recognized")
            return
        }
        #expect(try snapshots(fixture) == historical)
        let oldRoot = try #require(JSONSerialization.jsonObject(with: historicalCatalog) as? [String: Any])
        let oldEntries = try #require(oldRoot["models"] as? [[String: Any]])
        #expect(
            oldEntries.compactMap { $0["slug"] as? String } == [
                "local/qwen", "local:qwen", "native", "little-switch-auto-review",
            ])
        #expect(oldEntries[2]["base_instructions"] as? String == "Do not rewrite local:qwen or local/qwen")

        try fixture.manager.activate(providers: fixture.providers, configuration: fixture.configuration)
        #expect(try snapshots(fixture) == current)
        try fixture.manager.activate(
            providers: fixture.providers, configuration: fixture.configuration, signature: applied)
        #expect(try snapshots(fixture) == historical)
    }

    private func snapshots(_ fixture: CodexProfileFixture) throws -> [Data] {
        try fixture.paths.managedFiles.map { try Data(contentsOf: $0) }
    }
}
