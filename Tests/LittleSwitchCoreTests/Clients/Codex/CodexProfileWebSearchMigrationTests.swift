import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex profile web search migration")
struct CodexProfileWebSearchMigrationTests {
    @Test(
        "Legacy profiles capture their search mode on upgrade and restore it on disconnect",
        arguments: [nil, "cached", "indexed", "disabled", "live"] as [String?], [false, true]
    )
    func upgradeAndRestore(originalMode: String?, hasConcurrency: Bool) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let legacy = try LegacyCodexSearchProfile.install(
            fixture: fixture, originalMode: originalMode, hasConcurrency: hasConcurrency
        )

        #expect(try fixture.manager.status(expected: legacy.expected) == .requiresUpdate(legacy.applied))
        #expect(try snapshots(fixture) == legacy.files)

        try fixture.manager.activate(providers: fixture.providers, configuration: fixture.configuration)
        try fixture.manager.activate(providers: fixture.providers, configuration: fixture.configuration)

        let managed = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(try CodexTOMLEditor.rootString("web_search", in: managed) == "live")
        #expect(try fixture.manager.status(expected: legacy.expected) == .active(legacy.expected))
        let state = try JSONDecoder().decode(
            CodexProfileRestoreState.self, from: Data(contentsOf: fixture.paths.restoreState)
        )
        #expect(
            state.rootValues["web_search"]
                == CodexRootStringState(
                    wasPresent: originalMode != nil,
                    value: originalMode ?? "",
                    originalAssignment: originalMode.map { "web_search = \"\($0)\"" }
                )
        )

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(
            restored.trimmingCharacters(in: .whitespacesAndNewlines)
                == legacy.original.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("Disconnecting an old profile leaves its unowned search setting intact", arguments: [false, true])
    func restoreWithoutUpgrade(hasConcurrency: Bool) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let legacy = try LegacyCodexSearchProfile.install(
            fixture: fixture, originalMode: "cached", hasConcurrency: hasConcurrency
        )

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(
            restored.trimmingCharacters(in: .whitespacesAndNewlines)
                == legacy.original.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("Every managed write failure rolls a migration back byte for byte", arguments: [1, 2, 3])
    func failedMigration(failingWrite: Int) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let legacy = try LegacyCodexSearchProfile.install(
            fixture: fixture, originalMode: "cached", hasConcurrency: true
        )
        let manager = CodexProfileManager(
            paths: fixture.paths,
            fileStore: FaultingCodexProfileFileStore(
                backupDirectory: fixture.paths.backupDirectory,
                failingWrite: failingWrite
            )
        )

        #expect(throws: FaultingCodexProfileFileStore.Error.injected) {
            try manager.activate(providers: fixture.providers, configuration: fixture.configuration)
        }

        #expect(try snapshots(fixture) == legacy.files)
        #expect(try manager.status(expected: legacy.expected) == .requiresUpdate(legacy.applied))
    }

    @Test(
        "Reapplying the legacy signature undoes web search ownership after an upgrade",
        arguments: [nil, "cached", "indexed", "disabled", "live"] as [String?], [false, true]
    )
    func legacySignatureRollback(originalMode: String?, hasConcurrency: Bool) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let legacy = try LegacyCodexSearchProfile.install(
            fixture: fixture, originalMode: originalMode, hasConcurrency: hasConcurrency
        )

        try fixture.manager.activate(providers: fixture.providers, configuration: fixture.configuration)
        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration,
            signature: legacy.applied
        )

        #expect(try snapshots(fixture) == legacy.files)
        #expect(try fixture.manager.status(expected: legacy.expected) == .requiresUpdate(legacy.applied))
    }

    @Test("An untouched legacy signature does not start managing web search")
    func repeatedLegacyActivation() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let legacy = try LegacyCodexSearchProfile.install(
            fixture: fixture, originalMode: "disabled", hasConcurrency: false
        )

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration,
            signature: legacy.applied
        )

        #expect(try snapshots(fixture) == legacy.files)
    }

    @Test(
        "A missing journal never establishes ownership of a legacy search setting", arguments: ["cached", "disabled"])
    func restoreWithoutJournal(originalMode: String) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let legacy = try LegacyCodexSearchProfile.install(
            fixture: fixture, originalMode: originalMode, hasConcurrency: false
        )
        try FileManager.default.removeItem(at: fixture.paths.restoreState)

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(
            restored.trimmingCharacters(in: .whitespacesAndNewlines)
                == legacy.original.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test(
        "Restoring a search setting preserves its quoted key, value syntax and comment",
        arguments: ["web_search = 'cached' # original", "\"web_search\" = \"disabled\" # user"], [false, true]
    )
    func restoreOriginalAssignment(assignment: String, rollback: Bool) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let legacy = try LegacyCodexSearchProfile.install(
            fixture: fixture, originalMode: nil, hasConcurrency: false, originalAssignment: assignment
        )

        try fixture.manager.activate(providers: fixture.providers, configuration: fixture.configuration)
        if rollback {
            try fixture.manager.activate(
                providers: fixture.providers, configuration: fixture.configuration, signature: legacy.applied
            )
            #expect(try snapshots(fixture) == legacy.files)
        } else {
            try fixture.manager.restore()
            let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
            #expect(
                restored.trimmingCharacters(in: .whitespacesAndNewlines)
                    == legacy.original.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func snapshots(_ fixture: CodexProfileFixture) throws -> [Data] {
        try fixture.paths.managedFiles.map { try Data(contentsOf: $0) }
    }
}

private struct LegacyCodexSearchProfile {
    let original: String
    let expected: CodexManagedProfileSignature
    let applied: CodexManagedProfileSignature
    let files: [Data]

    static func install(
        fixture: CodexProfileFixture,
        originalMode: String?,
        hasConcurrency: Bool,
        originalAssignment: String? = nil
    ) throws -> Self {
        let original =
            ((originalAssignment ?? originalMode.map { "web_search = \"\($0)\"" }).map { $0 + "\n" } ?? "")
            + "approval_policy = \"on-request\"\n"
        let expected = try CodexManagedProfileSignature.resolve(
            providers: fixture.providers, configuration: fixture.configuration
        )
        var applied = expected.withoutManagedWebSearch()
        if !hasConcurrency {
            applied = applied.withoutNativeConcurrency()
        }
        var managed = try CodexTOMLEditor.activating(
            original, signature: applied, catalogPath: fixture.paths.catalog.path
        )
        var concurrency: CodexAgentConcurrencyState?
        if let maximum = applied.maximumConcurrentThreadsPerSession {
            let edit = try CodexAgentConcurrencyEditor.activating(
                managed, maximumConcurrentThreadsPerSession: maximum
            )
            managed = edit.text
            concurrency = edit.state
        }
        let originalRootValues = try Dictionary(
            uniqueKeysWithValues: [
                "profile", "model", "openai_base_url", "model_provider", "model_catalog_json",
                "model_reasoning_effort",
            ].map { key in
                (key, try CodexTOMLEditor.rootState(key, in: original))
            }
        )
        let journal = LegacySearchRestoreState(
            configExisted: true, rootValues: originalRootValues, agentConcurrency: concurrency
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let files = [Data(managed.utf8), expected.catalogData, try encoder.encode(journal)]
        for (url, data) in zip(fixture.paths.managedFiles, files) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        return Self(original: original, expected: expected, applied: applied, files: files)
    }
}

private struct LegacySearchRestoreState: Encodable {
    let configExisted: Bool
    let rootValues: [String: CodexRootStringState]
    let agentConcurrency: CodexAgentConcurrencyState?
}
