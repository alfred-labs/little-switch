import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Codex managed model identifier migration")
struct CodexIdentifierProfileMigrationTests {
    @Test(
        "Historical identifiers remain connected with an exact reversible upgrade",
        arguments: [false, true], [false, true]
    )
    func upgradeAndRollback(legacyReviewer: Bool, ownsSettings: Bool) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let historical = try HistoricalIdentifierProfile.install(
            fixture: fixture, legacyReviewer: legacyReviewer, ownsSettings: ownsSettings)

        guard
            case .requiresUpdate(let applied) = try fixture.manager.status(
                providers: fixture.providers, configuration: fixture.configuration, expected: historical.expected)
        else {
            Issue.record("A fully matching historical profile must require Apply, not disconnect")
            return
        }
        #expect(applied.modelSlug == "local/qwen")
        #expect(applied.catalogData == historical.files[1])
        #expect(applied.maximumConcurrentThreadsPerSession == (ownsSettings ? 4 : nil))
        #expect(applied.webSearchMode == (ownsSettings ? "live" : nil))
        #expect(try snapshots(fixture) == historical.files)

        try fixture.manager.activate(providers: fixture.providers, configuration: fixture.configuration)
        #expect(try fixture.manager.status(expected: historical.expected) == .active(historical.expected))
        let upgraded = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(try CodexTOMLEditor.rootString("model", in: upgraded) == "local:qwen")
        #expect(try CodexAgentConcurrencyEditor.currentValue(in: upgraded)?.value == 4)

        try fixture.manager.activate(
            providers: fixture.providers, configuration: fixture.configuration, signature: applied)
        #expect(try snapshots(fixture) == historical.files)
        #expect(
            try fixture.manager.status(
                providers: fixture.providers, configuration: fixture.configuration, expected: historical.expected)
                == .requiresUpdate(applied))

        try fixture.manager.restore()
        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(
            restored.trimmingCharacters(in: .whitespacesAndNewlines)
                == HistoricalIdentifierProfile.original.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("Identifier migration does not claim a drifted profile", arguments: HistoricalIdentifierDrift.allCases)
    func driftRemainsInactive(drift: HistoricalIdentifierDrift) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let historical = try HistoricalIdentifierProfile.install(fixture: fixture)
        switch drift {
        case .model:
            try rewrite(fixture.paths.config, from: "local/qwen", to: "local/another")
        case .catalog:
            try rewrite(fixture.paths.catalog, from: "262144", to: "400000")
        case .reviewer:
            try rewrite(
                fixture.paths.catalog, from: "Approval reviews via Local/qwen", to: "Approval reviews via Local/another"
            )
        case .concurrency:
            try rewrite(
                fixture.paths.config,
                from: "max_concurrent_threads_per_session = 4",
                to: "max_concurrent_threads_per_session = 5")
        case .search:
            try rewrite(fixture.paths.config, from: "web_search = \"live\"", to: "web_search = \"disabled\"")
        case .journal:
            try FileManager.default.removeItem(at: fixture.paths.restoreState)
        }
        #expect(
            try fixture.manager.status(
                providers: fixture.providers, configuration: fixture.configuration, expected: historical.expected)
                == .inactive)
    }

    @Test("Escaped case-sensitive identifiers reconstruct their exact former alias")
    func escapedIdentifier() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        var providers = fixture.providers
        providers[0].models = [DiscoveredModel(id: "Qwen/Code:1%")]
        let configuration = CodexConfiguration(
            defaultModel: ModelMapping(providerID: providers[0].id, modelID: "Qwen/Code:1%"))
        let expected = try CodexManagedProfileSignature.resolve(providers: providers, configuration: configuration)
        try fixture.manager.activate(providers: providers, configuration: configuration)
        try rewrite(fixture.paths.config, from: "local:%51wen%2f%43ode%3a1%25", to: "local/qwen/code:1%")
        try rewrite(fixture.paths.catalog, from: "local:%51wen%2f%43ode%3a1%25", to: "local/qwen/code:1%")

        guard
            case .requiresUpdate(let applied) = try fixture.manager.status(
                providers: providers, configuration: configuration, expected: expected)
        else {
            Issue.record("The old lowercased identifier must stay recognizable")
            return
        }
        #expect(applied.modelSlug == "local/qwen/code:1%")
        #expect(applied.catalogData == (try Data(contentsOf: fixture.paths.catalog)))
    }

    private func snapshots(_ fixture: CodexProfileFixture) throws -> [Data] {
        try fixture.paths.managedFiles.map { try Data(contentsOf: $0) }
    }

    private func rewrite(_ path: URL, from old: String, to new: String) throws {
        let source = try String(contentsOf: path, encoding: .utf8)
        #expect(source.contains(old))
        try Data(source.replacingOccurrences(of: old, with: new).utf8).write(to: path)
    }
}

enum HistoricalIdentifierDrift: CaseIterable, Sendable {
    case model, catalog, reviewer, concurrency, search, journal
}

private struct HistoricalIdentifierProfile {
    static let original = """
        model = "gpt-original"
        web_search = 'cached' # user
        agents.max_concurrent_threads_per_session = 9 # user
        approval_policy = "on-request"

        """

    let expected: CodexManagedProfileSignature
    let files: [Data]

    static func install(
        fixture: CodexProfileFixture,
        legacyReviewer: Bool = false,
        ownsSettings: Bool = true
    ) throws -> Self {
        try Data(original.utf8).write(to: fixture.paths.config)
        let expected = try CodexManagedProfileSignature.resolve(
            providers: fixture.providers, configuration: fixture.configuration)
        var source = expected
        if legacyReviewer { source = try source.withLegacyAutoReview() }
        if !ownsSettings { source = source.withoutNativeConcurrency().withoutManagedWebSearch() }
        try fixture.manager.activate(
            providers: fixture.providers, configuration: fixture.configuration, signature: source)
        for url in [fixture.paths.config, fixture.paths.catalog] {
            let current = try String(contentsOf: url, encoding: .utf8)
            #expect(current.contains("local:qwen"))
            try Data(current.replacingOccurrences(of: "local:qwen", with: "local/qwen").utf8).write(to: url)
        }
        return Self(expected: expected, files: try fixture.paths.managedFiles.map { try Data(contentsOf: $0) })
    }
}
