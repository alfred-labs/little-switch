import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex TOML editor")
struct CodexTOMLEditorTests {
    @Test("Activation preserves unrelated TOML and owns exact root and provider values")
    func activation() throws {
        let original = #"""
            # Root comment
            profile = "work"
            model = "first-party"
            approval_policy = "on-request"

            [model_providers.other]
            name = "Other"
            base_url = "https://example.com/v1"
            wire_api = "responses"

            [projects."/tmp/example"]
            trust_level = "trusted"
            """#

        let edited = try CodexTOMLEditor.activating(
            original,
            model: "little-switch-slug",
            catalogPath: "/tmp/model catalog.json"
        )

        #expect(try CodexTOMLEditor.rootString("profile", in: edited) == nil)
        #expect(try CodexTOMLEditor.rootString("model", in: edited) == "little-switch-slug")
        #expect(try CodexTOMLEditor.rootString("model_provider", in: edited) == nil)
        #expect(
            try CodexTOMLEditor.rootString("openai_base_url", in: edited)
                == "http://127.0.0.1:11436/v1"
        )
        #expect(
            try CodexTOMLEditor.rootString("model_catalog_json", in: edited)
                == "/tmp/model catalog.json"
        )
        #expect(
            try CodexTOMLEditor.string(at: ["model_providers", "little-switch", "name"], in: edited)
                == nil
        )
        #expect(edited.contains("# Root comment"))
        #expect(edited.contains("approval_policy = \"on-request\""))
        #expect(edited.contains("[model_providers.other]"))
        #expect(edited.contains("[projects.\"/tmp/example\"]"))
    }

    @Test("Activation migrates a legacy managed profile to the native endpoint shape")
    func migratesLegacyManagedProfile() throws {
        let legacy = #"""
            model = "little-switch/local/qwen"
            model_provider = "little-switch"

            [model_providers.little-switch]
            name = "LittleSwitch"
            base_url = "http://127.0.0.1:11436/v1/"
            wire_api = "responses"
            """#

        let edited = try CodexTOMLEditor.activating(
            legacy,
            model: "little-switch/local/qwen",
            catalogPath: "/tmp/catalog.json"
        )

        #expect(try CodexTOMLEditor.rootString("model_provider", in: edited) == nil)
        #expect(
            try CodexTOMLEditor.rootString("openai_base_url", in: edited)
                == "http://127.0.0.1:11436/v1"
        )
        #expect(!edited.contains("[model_providers.little-switch]"))
    }

    @Test("Managed detection requires the native endpoint shape")
    func rootIsManagedShape() throws {
        let native = #"""
            model = "little-switch/local/qwen"
            openai_base_url = "http://127.0.0.1:11436/v1"
            model_catalog_json = "/tmp/catalog.json"
            """#
        #expect(try CodexTOMLEditor.rootIsManaged(native, catalogPath: "/tmp/catalog.json"))

        let legacy = #"""
            model = "little-switch/local/qwen"
            model_provider = "little-switch"
            model_catalog_json = "/tmp/catalog.json"
            """#
        #expect(try !CodexTOMLEditor.rootIsManaged(legacy, catalogPath: "/tmp/catalog.json"))

        let foreign = #"""
            model = "little-switch/local/qwen"
            openai_base_url = "http://127.0.0.1:9999/v1"
            model_catalog_json = "/tmp/catalog.json"
            """#
        #expect(try !CodexTOMLEditor.rootIsManaged(foreign, catalogPath: "/tmp/catalog.json"))
    }

    @Test("Signature activation owns the resolved model slug")
    func signatureActivation() throws {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "qwen")]
        )
        let signature = try CodexManagedProfileSignature.resolve(
            providers: [provider],
            configuration: CodexConfiguration(
                defaultModel: ModelMapping(providerID: providerID, modelID: "qwen")
            )
        )

        let edited = try CodexTOMLEditor.activating(
            "",
            signature: signature,
            catalogPath: "/tmp/catalog.json"
        )

        #expect(try CodexTOMLEditor.rootString("model", in: edited) == signature.modelSlug)
    }

    @Test("Activation is idempotent and recognizes quoted owned table names")
    func idempotence() throws {
        let existing = #"""
            model = "old"

            [model_providers."little-switch"]
            name = "Stale"
            base_url = "http://127.0.0.1:1"
            wire_api = "responses"

            [features]
            shell_snapshot = true
            """#

        let first = try CodexTOMLEditor.activating(
            existing,
            model: "managed",
            catalogPath: "/tmp/catalog.json"
        )
        let second = try CodexTOMLEditor.activating(
            first,
            model: "managed",
            catalogPath: "/tmp/catalog.json"
        )

        #expect(second == first)
        // The owned provider table belongs to the pre-native shape: a stale
        // quoted table is removed and no canonical table is written anymore.
        #expect(!second.contains("model_providers"))
        #expect(second.contains("[features]"))
    }

    @Test("Malformed TOML is rejected before editing")
    func malformed() {
        #expect(throws: (any Swift.Error).self) {
            try CodexTOMLEditor.activating(
                "model = [",
                model: "managed",
                catalogPath: "/tmp/catalog.json"
            )
        }
    }

    @Test("Non-string root values are rejected by every root operation")
    func nonStringRoots() {
        #expect(throws: CodexTOMLEditor.Error.nonStringRootValue("model")) {
            try CodexTOMLEditor.rootString("model", in: "model = 1")
        }
        #expect(throws: CodexTOMLEditor.Error.nonStringRootValue("model")) {
            try CodexTOMLEditor.rootState("model", in: "model = 1")
        }
        #expect(throws: CodexTOMLEditor.Error.nonStringRootValue("model")) {
            try CodexTOMLEditor.activating(
                "model = 1",
                model: "managed",
                catalogPath: "/tmp/catalog.json"
            )
        }
        #expect(throws: CodexTOMLEditor.Error.nonStringRootValue("profile")) {
            try CodexTOMLEditor.activating(
                "profile = 1",
                model: "managed",
                catalogPath: "/tmp/catalog.json"
            )
        }
    }

    @Test("Multiline root assignments report unsupported syntax")
    func unsupportedRootSyntax() {
        let model = "model = \"\"\"\nmanaged\n\"\"\""
        #expect(throws: CodexTOMLEditor.Error.unsupportedRootSyntax("model")) {
            try CodexTOMLEditor.activating(
                model,
                model: "replacement",
                catalogPath: "/tmp/catalog.json"
            )
        }
        let profile = "profile = \"\"\"\nwork\n\"\"\""
        #expect(throws: CodexTOMLEditor.Error.unsupportedRootSyntax("profile")) {
            try CodexTOMLEditor.activating(
                profile,
                model: "managed",
                catalogPath: "/tmp/catalog.json"
            )
        }
    }

    @Test("Missing roots and table paths return absent states")
    func missingValues() throws {
        let text = """
            [features]
            shell_snapshot = true

            [projects.example]
            path = "/tmp/example"
            """

        #expect(try CodexTOMLEditor.rootString("model", in: text) == nil)
        #expect(try CodexTOMLEditor.string(at: [], in: text) == nil)
        #expect(try CodexTOMLEditor.string(at: ["missing", "value"], in: text) == nil)
        #expect(
            try CodexTOMLEditor.string(at: ["projects", "example", "path"], in: text) == "/tmp/example"
        )
        #expect(
            try CodexTOMLEditor.rootState("model", in: text)
                == CodexRootStringState(wasPresent: false, value: "")
        )
    }

    @Test("Restoration replaces present roots and skips unspecified roots")
    func rootRestoration() throws {
        let restored = try CodexTOMLEditor.restoring(
            "model = \"managed\"\nmodel_provider = \"little-switch\"",
            states: [
                "model": CodexRootStringState(wasPresent: true, value: "original"),
                "model_provider": CodexRootStringState(wasPresent: false, value: ""),
            ]
        )

        #expect(try CodexTOMLEditor.rootString("model", in: restored) == "original")
        #expect(try CodexTOMLEditor.rootString("model_provider", in: restored) == nil)
    }

    @Test("Supported TOML strings round-trip exactly")
    func supportedStringRoundTrip() throws {
        let values = [
            "",
            "plain",
            "unicode 🌍 café",
            "quote \" and backslash \\",
            "first line\nsecond line",
        ]

        for value in values {
            let edited = try CodexTOMLEditor.activating(
                "",
                model: value,
                catalogPath: value
            )
            #expect(try CodexTOMLEditor.rootString("model", in: edited) == value)
            #expect(try CodexTOMLEditor.rootString("model_catalog_json", in: edited) == value)
        }
    }

    @Test("TOML strings that do not round-trip report a typed error")
    func unsupportedStringScalars() {
        let nul = "prefix\u{0000}suffix"
        #expect(throws: CodexTOMLEditor.Error.unrepresentableString(nul)) {
            try CodexTOMLEditor.activating(
                "",
                model: nul,
                catalogPath: "/tmp/catalog.json"
            )
        }

        let delete = "prefix\u{007F}suffix"
        #expect(throws: CodexTOMLEditor.Error.unrepresentableString(delete)) {
            try CodexTOMLEditor.activating(
                "",
                model: delete,
                catalogPath: "/tmp/catalog.json"
            )
        }
    }

    @Test("Owned provider removal handles adjacent blocks and absent blocks")
    func ownedProviderRemoval() throws {
        let adjacent = #"""
            [model_providers.little-switch]
            name = "LittleSwitch"
            base_url = "http://127.0.0.1:11436/v1/"
            wire_api = "responses"
            [features]
            shell_snapshot = true
            """#
        let removed = try CodexTOMLEditor.removingOwnedProvider(from: adjacent)
        #expect(!removed.contains("[model_providers.little-switch]"))
        #expect(removed.contains("[features]"))

        let absent = "[features]\nshell_snapshot = true"
        #expect(try CodexTOMLEditor.removingOwnedProvider(from: absent) == absent)
    }

    @Test("Activation handles an empty document and scans non-table array lines")
    func emptyAndNonTableScans() throws {
        let activated = try CodexTOMLEditor.activating(
            "",
            model: "managed",
            catalogPath: "/tmp/catalog.json"
        )
        #expect(try CodexTOMLEditor.rootString("model", in: activated) == "managed")

        let array = "values = [\n  [\"nested\"],\n]"
        #expect(try CodexTOMLEditor.removingOwnedProvider(from: array) == array)

        let probeNamedTable = "[__little_switch_probe]\nvalue = true"
        #expect(
            try CodexTOMLEditor.removingOwnedProvider(from: probeNamedTable)
                == probeNamedTable
        )

        let nestedProbeNamedTable = "[__little_switch_probe.child]\nvalue = true"
        #expect(
            try CodexTOMLEditor.removingOwnedProvider(from: nestedProbeNamedTable)
                == nestedProbeNamedTable
        )

        let arrayTable = "[[projects]]\npath = \"/tmp/project\""
        #expect(try CodexTOMLEditor.removingOwnedProvider(from: arrayTable) == arrayTable)
    }
}

extension CodexTOMLEditorTests {
    @Test("Activation sets the managed default reasoning effort")
    func defaultReasoningEffort() throws {
        let activated = try CodexTOMLEditor.activating(
            "",
            model: "managed",
            catalogPath: "/tmp/catalog.json"
        )
        #expect(try CodexTOMLEditor.rootString("model_reasoning_effort", in: activated) == "max")

        let replaced = try CodexTOMLEditor.activating(
            "model_reasoning_effort = \"high\"",
            model: "managed",
            catalogPath: "/tmp/catalog.json"
        )
        #expect(try CodexTOMLEditor.rootString("model_reasoning_effort", in: replaced) == "max")
    }

    @Test("Bracket-leading multiline string content never delimits a TOML section")
    func multilineStringContentIsNotAHeader() throws {
        let rootString = #"""
            message = '''
            [not-a-table]
            '''

            [model_providers.little-switch]
            name = "Stale"
            """#
        let activated = try CodexTOMLEditor.activating(
            rootString,
            model: "managed",
            catalogPath: "/tmp/catalog.json"
        )
        #expect(try CodexTOMLEditor.rootString("message", in: activated) == "[not-a-table]\n")
        #expect(try CodexTOMLEditor.rootString("model", in: activated) == "managed")

        let providerString = #"""
            [model_providers.little-switch]
            description = '''
            [not-a-table]
            '''
            [features]
            enabled = true
            """#
        #expect(
            try CodexTOMLEditor.removingOwnedProvider(from: providerString)
                == "[features]\nenabled = true"
        )
    }

    @Test(
        "Activation preserves nested array elements when locating the root section",
        arguments: [true, false]
    )
    func activationPreservesNestedArrays(trailingComma: Bool) throws {
        let array = nestedArray(trailingComma: trailingComma)
        let original = """
            \(array)

            [model_providers.little-switch]
            name = "Stale"
            base_url = "http://127.0.0.1:1"
            wire_api = "responses"
            """

        let activated = try CodexTOMLEditor.activating(
            original,
            model: "managed",
            catalogPath: "/tmp/catalog.json"
        )

        #expect(activated.hasPrefix(array))
        #expect(try CodexTOMLEditor.rootString("model", in: activated) == "managed")
        #expect(
            try CodexTOMLEditor.string(
                at: ["model_providers", "little-switch", "name"],
                in: activated
            ) == nil
        )
    }

    @Test(
        "Removal treats nested array elements as provider content",
        arguments: [true, false]
    )
    func removalPreservesFollowingTableAfterNestedArrays(trailingComma: Bool) throws {
        let original = """
            [model_providers.little-switch]
            name = "Stale"
            values = [
              ["nested"]\(trailingComma ? "," : "")
            ]
            [features]
            enabled = true
            """

        #expect(
            try CodexTOMLEditor.removingOwnedProvider(from: original)
                == "[features]\nenabled = true"
        )
    }

    private func nestedArray(trailingComma: Bool) -> String {
        """
        values = [
          ["nested"]\(trailingComma ? "," : "")
        ]
        """
    }
}
