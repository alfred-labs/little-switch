import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex profile native concurrency")
struct CodexProfileConcurrencyTests {
    @Test("A legacy journal stays connected and the first apply captures user state")
    func legacyUpgradeAndRestore() throws {
        let fixture = try CodexProfileFixture.make(maximumParallelRequests: 7)
        defer { fixture.remove() }
        let original = "agents.max_concurrent_threads_per_session = 9 # user\n"
        let legacy = try installLegacyProfile(original: original, fixture: fixture)
        let signature = try resolvedSignature(fixture)

        #expect(
            try fixture.manager.status(expected: signature)
                == .requiresUpdate(signature.withoutNativeConcurrency().withoutManagedWebSearch())
        )

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration,
            signature: signature
        )
        var journal = try currentJournal(fixture)
        #expect(journal.agentConcurrency?.originalWasPresent == true)
        #expect(journal.agentConcurrency?.originalValue == 9)
        #expect(journal.agentConcurrency?.originalSyntax == .dotted)
        #expect(journal.agentConcurrency?.originalToken == "9")
        #expect(journal.agentConcurrency?.lastManagedValue == 7)
        #expect(journal.agentConcurrency?.managedSyntax == .dotted)

        var updatedProviders = fixture.providers
        updatedProviders[0].maximumParallelRequests = 5
        let updatedSignature = try CodexManagedProfileSignature.resolve(
            providers: updatedProviders,
            configuration: fixture.configuration
        )
        try fixture.manager.activate(
            providers: updatedProviders,
            configuration: fixture.configuration,
            signature: updatedSignature
        )
        journal = try currentJournal(fixture)
        #expect(journal.agentConcurrency?.originalValue == 9)
        #expect(journal.agentConcurrency?.originalToken == "9")
        #expect(journal.agentConcurrency?.lastManagedValue == 5)
        #expect(
            try fixture.manager.status(expected: updatedSignature)
                == .active(updatedSignature)
        )

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(restored.contains(original.trimmingCharacters(in: .newlines)))
        #expect(try CodexAgentConcurrencyEditor.currentValue(in: restored)?.value == 9)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.catalog.path))
        #expect(legacy.catalog == updatedSignature.catalogData)
    }

    @Test("Unsupported agent syntax rejects activation before any file mutation")
    func unsupportedSyntaxHasNoSideEffects() throws {
        let fixture = try CodexProfileFixture.make(maximumParallelRequests: 7)
        defer { fixture.remove() }
        let config = Data(
            "agents = { max_concurrent_threads_per_session = 3 }\n".utf8
        )
        let catalog = Data("prior catalog".utf8)
        let journal = Data("prior journal".utf8)
        try install(config, at: fixture.paths.config)
        try install(catalog, at: fixture.paths.catalog)
        try install(journal, at: fixture.paths.restoreState)
        let signature = try resolvedSignature(fixture)

        #expect(throws: CodexAgentConcurrencyEditor.Error.inlineAgentsTable) {
            try fixture.manager.activate(
                providers: fixture.providers,
                configuration: fixture.configuration,
                signature: signature
            )
        }

        #expect(try Data(contentsOf: fixture.paths.config) == config)
        #expect(try Data(contentsOf: fixture.paths.catalog) == catalog)
        #expect(try Data(contentsOf: fixture.paths.restoreState) == journal)
    }

    @Test("Restore owns the agent value even when managed root values drift")
    func restoreAgentDespiteRootDrift() throws {
        let fixture = try CodexProfileFixture.make(maximumParallelRequests: 7)
        defer { fixture.remove() }
        let original = "agents.max_concurrent_threads_per_session = 11 # original\n"
        try install(Data(original.utf8), at: fixture.paths.config)
        let signature = try resolvedSignature(fixture)
        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration,
            signature: signature
        )
        var drifted = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        drifted = drifted.replacingOccurrences(
            of: "openai_base_url = \"http://127.0.0.1:11436/v1\"",
            with: "openai_base_url = \"http://127.0.0.1:1/v1\""
        )
        try install(Data(drifted.utf8), at: fixture.paths.config)

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(restored.contains(original.trimmingCharacters(in: .newlines)))
        #expect(
            try CodexTOMLEditor.rootString("openai_base_url", in: restored)
                == "http://127.0.0.1:1/v1"
        )
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
    }

    @Test("Restore preserves a user drift to a noninteger agent value")
    func restorePreservesNonIntegerDrift() throws {
        let fixture = try CodexProfileFixture.make(maximumParallelRequests: 7)
        defer { fixture.remove() }
        try install(Data("# original\n".utf8), at: fixture.paths.config)
        let signature = try resolvedSignature(fixture)
        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration,
            signature: signature
        )
        var drifted = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        drifted = drifted.replacingOccurrences(
            of: "max_concurrent_threads_per_session = 7",
            with: #"max_concurrent_threads_per_session = "manual""#
        )
        try install(Data(drifted.utf8), at: fixture.paths.config)

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(restored.contains(#"max_concurrent_threads_per_session = "manual""#))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
    }

    @Test("Status requires a journal and verifies its managed agent value")
    func statusVerification() throws {
        let fixture = try CodexProfileFixture.make(maximumParallelRequests: 7)
        defer { fixture.remove() }
        let signature = try resolvedSignature(fixture)
        let arbitraryManaged = try CodexTOMLEditor.activating(
            "",
            signature: signature,
            catalogPath: fixture.paths.catalog.path
        )
        try install(Data(arbitraryManaged.utf8), at: fixture.paths.config)
        try install(signature.catalogData, at: fixture.paths.catalog)

        #expect(try fixture.manager.status(expected: signature) == .inactive)

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration,
            signature: signature
        )
        #expect(try fixture.manager.status(expected: signature) == .active(signature))
        #expect(
            try fixture.manager.status(
                providers: fixture.providers,
                configuration: fixture.configuration,
                expected: signature
            ) == .active(signature)
        )

        var unsupported = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        unsupported = unsupported.replacingOccurrences(
            of: "max_concurrent_threads_per_session = 7",
            with: "max_threads = 7"
        )
        try install(Data(unsupported.utf8), at: fixture.paths.config)
        #expect(try fixture.manager.status(expected: signature) == .inactive)

        let supportedAgain = unsupported.replacingOccurrences(
            of: "max_threads = 7",
            with: "max_concurrent_threads_per_session = 7"
        )
        try install(Data(supportedAgain.utf8), at: fixture.paths.config)

        var drifted = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        drifted = drifted.replacingOccurrences(
            of: "max_concurrent_threads_per_session = 7",
            with: "max_concurrent_threads_per_session = 5"
        )
        try install(Data(drifted.utf8), at: fixture.paths.config)
        #expect(try fixture.manager.status(expected: signature) == .inactive)

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration,
            signature: signature
        )
        var journal = try Data(contentsOf: fixture.paths.restoreState)
        let managedValue = Data(#""lastManagedValue" : 7"#.utf8)
        let staleValue = Data(#""lastManagedValue" : 5"#.utf8)
        #expect(journal.contains(managedValue))
        journal.replaceSubrange(try #require(journal.range(of: managedValue)), with: staleValue)
        try install(journal, at: fixture.paths.restoreState)
        #expect(try fixture.manager.status(expected: signature) == .inactive)
    }

    @Test("A transaction failure restores config, catalog, and journal byte for byte")
    func transactionRollback() throws {
        let fixture = try CodexProfileFixture.make(maximumParallelRequests: 7)
        defer { fixture.remove() }
        let config = Data("agents.max_concurrent_threads_per_session = 8\n".utf8)
        let catalog = Data("prior catalog".utf8)
        let journal = Data("prior journal".utf8)
        try install(config, at: fixture.paths.config)
        try install(catalog, at: fixture.paths.catalog)
        try install(journal, at: fixture.paths.restoreState)
        let manager = CodexProfileManager(
            paths: fixture.paths,
            fileStore: FaultingCodexProfileFileStore(
                backupDirectory: fixture.paths.backupDirectory,
                failingWrite: 3
            )
        )
        let signature = try resolvedSignature(fixture)

        #expect(throws: FaultingCodexProfileFileStore.Error.injected) {
            try manager.activate(
                providers: fixture.providers,
                configuration: fixture.configuration,
                signature: signature
            )
        }

        #expect(try Data(contentsOf: fixture.paths.config) == config)
        #expect(try Data(contentsOf: fixture.paths.catalog) == catalog)
        #expect(try Data(contentsOf: fixture.paths.restoreState) == journal)
    }

    @Test("The explicit legacy signature rolls an upgrade back exactly")
    func legacyRollback() throws {
        let fixture = try CodexProfileFixture.make(maximumParallelRequests: 7)
        defer { fixture.remove() }
        let original = "agents.max_concurrent_threads_per_session = 9 # user\n"
        let legacy = try installLegacyProfile(original: original, fixture: fixture)
        let signature = try resolvedSignature(fixture)
        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration,
            signature: signature
        )

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration,
            signature: signature.withoutNativeConcurrency().withoutManagedWebSearch()
        )

        #expect(try Data(contentsOf: fixture.paths.config) == legacy.config)
        #expect(try Data(contentsOf: fixture.paths.catalog) == legacy.catalog)
        #expect(try Data(contentsOf: fixture.paths.restoreState) == legacy.journal)
        #expect(
            try fixture.manager.status(expected: signature)
                == .requiresUpdate(signature.withoutNativeConcurrency().withoutManagedWebSearch())
        )
    }

    private func resolvedSignature(
        _ fixture: CodexProfileFixture
    ) throws -> CodexManagedProfileSignature {
        try CodexManagedProfileSignature.resolve(
            providers: fixture.providers,
            configuration: fixture.configuration
        )
    }

    private func installLegacyProfile(
        original: String,
        fixture: CodexProfileFixture
    ) throws -> LegacyProfileFiles {
        let signature = try resolvedSignature(fixture)
        let managed = try CodexTOMLEditor.activating(
            original,
            signature: signature.withoutManagedWebSearch(),
            catalogPath: fixture.paths.catalog.path
        )
        let rootValues = try Dictionary(
            uniqueKeysWithValues: [
                "profile",
                "model",
                "openai_base_url",
                "model_provider",
                "model_catalog_json",
            ].map { key in
                (key, try CodexTOMLEditor.rootState(key, in: original))
            }
        )
        let journal = try encoded(
            LegacyRestoreState(configExisted: true, rootValues: rootValues)
        )
        let config = Data(managed.utf8)
        try install(config, at: fixture.paths.config)
        try install(signature.catalogData, at: fixture.paths.catalog)
        try install(journal, at: fixture.paths.restoreState)
        return LegacyProfileFiles(
            config: config,
            catalog: signature.catalogData,
            journal: journal
        )
    }

    private func currentJournal(
        _ fixture: CodexProfileFixture
    ) throws -> CurrentRestoreState {
        try JSONDecoder().decode(
            CurrentRestoreState.self,
            from: Data(contentsOf: fixture.paths.restoreState)
        )
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func install(_ data: Data, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }
}

private struct LegacyRestoreState: Codable {
    let configExisted: Bool
    let rootValues: [String: CodexRootStringState]
}

private struct LegacyProfileFiles {
    let config: Data
    let catalog: Data
    let journal: Data
}

private struct CurrentRestoreState: Codable {
    let configExisted: Bool
    let rootValues: [String: CodexRootStringState]
    let agentConcurrency: CodexAgentConcurrencyState?
}
