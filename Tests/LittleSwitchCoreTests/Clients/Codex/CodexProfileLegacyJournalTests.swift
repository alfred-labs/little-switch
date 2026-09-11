import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex legacy profile journal")
struct CodexProfileLegacyJournalTests {
    @Test("Migration captures only the newly managed endpoint and leaves search capture pending")
    func capturesEndpointWithoutCapturingWebSearch() throws {
        let original = CodexProfileRestoreState(configExisted: true, rootValues: [:], agentConcurrency: nil)
        let data = try JSONEncoder().encode(original)

        let migrated = try CodexProfileLegacyJournal.decoded(
            data,
            configText: "openai_base_url = 'https://openai-proxy.example/v1'\nweb_search = 'cached'"
        )

        #expect(
            migrated.rootValues == [
                "openai_base_url": CodexRootStringState(wasPresent: true, value: "https://openai-proxy.example/v1")
            ]
        )
    }

    @Test("Migration never replaces a previously journaled endpoint")
    func preservesJournaledEndpoint() throws {
        let original = CodexProfileRestoreState(
            configExisted: true,
            rootValues: [
                "openai_base_url": CodexRootStringState(wasPresent: true, value: "https://original.example/v1")
            ],
            agentConcurrency: nil
        )

        #expect(
            try CodexProfileLegacyJournal.decoded(
                JSONEncoder().encode(original),
                configText: "openai_base_url = '\(CodexTOMLEditor.baseURL)'"
            ) == original
        )
    }

    @Test("Legacy profiles preserve an existing OpenAI endpoint", arguments: [false, true], [false, true])
    func legacyJournalPreservesOpenAIEndpoint(reactivate: Bool, hasJournal: Bool) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let legacy = """
            model = "little-switch/local/qwen"
            model_provider = "little-switch"
            openai_base_url = "https://openai-proxy.example/v1"
            model_catalog_json = "\(fixture.paths.catalog.path)"

            [model_providers.little-switch]
            name = "LittleSwitch"
            base_url = "http://127.0.0.1:11436/v1/"
            wire_api = "responses"
            """
        try Data(legacy.utf8).write(to: fixture.paths.config)
        try FileManager.default.createDirectory(
            at: fixture.paths.restoreState.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let journal = #"""
            {
              "configExisted": true,
              "rootValues": {
                "model": { "wasPresent": true, "value": "gpt-first-party" },
                "model_provider": { "wasPresent": false, "value": "" },
                "model_catalog_json": { "wasPresent": false, "value": "" }
              }
            }
            """#
        if hasJournal {
            try Data(journal.utf8).write(to: fixture.paths.restoreState)
        }

        if reactivate {
            try fixture.manager.activate(
                providers: fixture.providers,
                configuration: fixture.configuration
            )
        }
        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(
            try CodexTOMLEditor.rootString("openai_base_url", in: restored)
                == "https://openai-proxy.example/v1"
        )
        #expect(try CodexTOMLEditor.rootString("model", in: restored) == (hasJournal ? "gpt-first-party" : nil))
    }

    @Test("A legacy managed profile without a journal restores to unmanaged")
    func legacyMigrationRestore() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let legacy = #"""
            model = "little-switch/local/qwen"
            model_provider = "little-switch"

            [model_providers.little-switch]
            name = "LittleSwitch"
            base_url = "http://127.0.0.1:11436/v1/"
            wire_api = "responses"
            """#
        try Data(legacy.utf8).write(to: fixture.paths.config)

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )
        let managed = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(try CodexTOMLEditor.rootString("model_provider", in: managed) == nil)

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(try CodexTOMLEditor.rootString("model_provider", in: restored) == nil)
        #expect(try CodexTOMLEditor.rootString("model", in: restored) == nil)
        #expect(!restored.contains("[model_providers.little-switch]"))
    }

    @Test("A native managed profile without a journal restores to unmanaged")
    func nativeMigrationRestore() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        // A desktop-drifted native profile: managed keys carry values the
        // app itself wrote (a selected native model), and no journal
        // survives to prove they predate LittleSwitch. Capturing them as
        // user state would poison every later restore into re-applying
        // the gateway wiring, so the journal must treat them as absent.
        let native = """
            model = "gpt-5.6-sol"
            model_reasoning_effort = "medium"
            openai_base_url = "\(CodexTOMLEditor.baseURL)"
            model_catalog_json = "\(fixture.paths.catalog.path)"
            """
        try Data(native.utf8).write(to: fixture.paths.config)

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(try CodexTOMLEditor.rootString("openai_base_url", in: restored) == nil)
        #expect(try CodexTOMLEditor.rootString("model_catalog_json", in: restored) == nil)
        #expect(try CodexTOMLEditor.rootString("model", in: restored) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.catalog.path))
    }

    @Test("A legacy managed profile reuses the pre-native journal")
    func legacyJournalMigration() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let legacy = """
            model = "little-switch/local/qwen"
            model_provider = "little-switch"
            model_catalog_json = "\(fixture.paths.catalog.path)"

            [model_providers.little-switch]
            name = "LittleSwitch"
            base_url = "http://127.0.0.1:11436/v1/"
            wire_api = "responses"
            """
        try Data(legacy.utf8).write(to: fixture.paths.config)
        try FileManager.default.createDirectory(
            at: fixture.paths.restoreState.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let journal = #"""
            {
              "configExisted" : true,
              "rootValues" : {
                "model" : { "wasPresent" : true, "value" : "gpt-first-party" },
                "model_provider" : { "wasPresent" : false, "value" : "" },
                "model_reasoning_effort" : { "wasPresent" : true, "value" : "max" }
              }
            }
            """#
        try Data(journal.utf8).write(to: fixture.paths.restoreState)

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )
        let state = try JSONDecoder().decode(
            CodexProfileRestoreState.self,
            from: Data(contentsOf: fixture.paths.restoreState)
        )
        #expect(state.rootValues["model"]?.value == "gpt-first-party")

        try fixture.manager.restore()
        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(try CodexTOMLEditor.rootString("model", in: restored) == "gpt-first-party")
        #expect(try CodexTOMLEditor.rootString("model_provider", in: restored) == nil)
        #expect(try CodexTOMLEditor.rootString("openai_base_url", in: restored) == nil)
        #expect(!restored.contains("[model_providers.little-switch]"))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
    }
}
