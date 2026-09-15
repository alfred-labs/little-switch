import Testing

@testable import LittleSwitchCore

@Suite("Codex agent concurrency editor")
struct CodexAgentConcurrencyEditorTests {
    @Test("Every concurrency editor error has stable product-facing copy")
    func errorDescriptions() {
        let expected: [(CodexAgentConcurrencyEditor.Error, String)] = [
            (
                .inlineAgentsTable,
                CoreL10n.string(
                    "The `agents` entry in ~/.codex/config.toml is an inline table. Rewrite it as an `[agents]` section and try again."
                )
            ),
            (
                .unsupportedAgentsSyntax,
                CoreL10n.string(
                    "The `agents` entry in ~/.codex/config.toml is not a table. Rewrite it as an `[agents]` section and try again."
                )
            ),
            (
                .legacyAlias,
                CoreL10n.string(
                    "The legacy `agents.max_threads` key in ~/.codex/config.toml conflicts with the managed concurrency limit. Remove it and try again."
                )
            ),
            (
                .nonIntegerManagedValue,
                CoreL10n.string(
                    "The `agents.max_concurrent_threads_per_session` value in ~/.codex/config.toml is not an integer. Fix it and try again."
                )
            ),
            (
                .unsupportedManagedSyntax,
                CoreL10n.string(
                    "The `agents.max_concurrent_threads_per_session` assignments in ~/.codex/config.toml conflict. Keep a single one and try again."
                )
            ),
        ]

        #expect(expected.map(\.0.errorDescription) == expected.map { Optional($0.1) })
    }

    @Test("Canonical activation and restoration replace only the integer token")
    func canonicalReplacementAndRestore() throws {
        let original = #"""
            # Root
            [agents]
              max_concurrent_threads_per_session   =   0x08 # user format
            role = "worker"
            """#

        let edit = try CodexAgentConcurrencyEditor.activating(
            original,
            maximumConcurrentThreadsPerSession: 7
        )

        #expect(
            edit.text
                == #"""
                # Root
                [agents]
                  max_concurrent_threads_per_session   =   7 # user format
                role = "worker"
                """#
        )
        #expect(edit.state.originalWasPresent)
        #expect(edit.state.originalValue == 8)
        #expect(edit.state.originalSyntax == .canonical)
        #expect(edit.state.lastManagedValue == 7)
        #expect(!edit.state.createdAgentsTable)
        #expect(
            try CodexAgentConcurrencyEditor.restoring(edit.text, state: edit.state)
                == original
        )
    }

    @Test("Dotted activation and restoration preserve spacing and comments")
    func dottedReplacementAndRestore() throws {
        let original =
            "agents . max_concurrent_threads_per_session = +8  # keep\napproval_policy = \"on-request\""

        let edit = try CodexAgentConcurrencyEditor.activating(
            original,
            maximumConcurrentThreadsPerSession: 7
        )

        #expect(
            edit.text
                == "agents . max_concurrent_threads_per_session = 7  # keep\napproval_policy = \"on-request\""
        )
        #expect(edit.state.originalSyntax == .dotted)
        #expect(
            try CodexAgentConcurrencyEditor.restoring(edit.text, state: edit.state)
                == original
        )
    }

    @Test("Activation inserts into an existing agents table without owning its header")
    func canonicalInsertion() throws {
        let original = #"""
            [agents]
            # User table
            role = "worker"
            """#

        let edit = try CodexAgentConcurrencyEditor.activating(
            original,
            maximumConcurrentThreadsPerSession: 6
        )

        #expect(
            edit.text
                == #"""
                [agents]
                # User table
                role = "worker"
                max_concurrent_threads_per_session = 6
                """#
        )
        #expect(!edit.state.originalWasPresent)
        #expect(edit.state.originalSyntax == nil)
        #expect(edit.state.managedSyntax == .canonical)
        #expect(!edit.state.createdAgentsTable)
        #expect(
            try CodexAgentConcurrencyEditor.restoring(edit.text, state: edit.state)
                == original
        )
    }

    @Test("Activation extends an existing dotted agents family")
    func dottedInsertion() throws {
        let original =
            "agents.max_depth = 3\napproval_policy = \"on-request\""

        let edit = try CodexAgentConcurrencyEditor.activating(
            original,
            maximumConcurrentThreadsPerSession: 5
        )

        #expect(
            edit.text
                == "agents.max_depth = 3\nagents.max_concurrent_threads_per_session = 5\napproval_policy = \"on-request\""
        )
        #expect(edit.state.managedSyntax == .dotted)
        #expect(!edit.state.createdAgentsTable)
        #expect(
            try CodexAgentConcurrencyEditor.restoring(edit.text, state: edit.state)
                == original
        )
    }

    @Test("Activation creates and later removes an otherwise empty agents table")
    func absentCreationAndCleanup() throws {
        for original in ["", "approval_policy = \"on-request\""] {
            let edit = try CodexAgentConcurrencyEditor.activating(
                original,
                maximumConcurrentThreadsPerSession: 4
            )

            #expect(edit.state.createdAgentsTable)
            #expect(edit.state.managedSyntax == .canonical)
            #expect(
                try CodexAgentConcurrencyEditor.restoring(edit.text, state: edit.state)
                    == original
            )
        }
    }

    @Test("A created parent table is cleaned up without touching a nested agents table")
    func nestedTableSurvivesCleanup() throws {
        let original = #"""
            [agents.worker]
            role = "reviewer"

            [features]
            enabled = true
            """#

        let edit = try CodexAgentConcurrencyEditor.activating(
            original,
            maximumConcurrentThreadsPerSession: 4
        )

        #expect(edit.text.hasPrefix("[agents]\nmax_concurrent_threads_per_session = 4\n"))
        #expect(edit.state.createdAgentsTable)
        #expect(
            try CodexAgentConcurrencyEditor.restoring(edit.text, state: edit.state)
                == original
        )
    }

    @Test("Cleanup retains a created agents header when user content remains")
    func createdHeaderRetention() throws {
        let edit = try CodexAgentConcurrencyEditor.activating(
            "",
            maximumConcurrentThreadsPerSession: 4
        )
        let withUserContent = edit.text + "\nrole = \"reviewer\""

        let restored = try CodexAgentConcurrencyEditor.restoring(
            withUserContent,
            state: edit.state
        )

        #expect(restored == "[agents]\nrole = \"reviewer\"")
    }

    @Test("Repeated activation preserves the original and updates last managed value")
    func repeatedActivation() throws {
        let original = "[agents]\nmax_concurrent_threads_per_session = 9"
        let first = try CodexAgentConcurrencyEditor.activating(
            original,
            maximumConcurrentThreadsPerSession: 7
        )

        let second = try CodexAgentConcurrencyEditor.activating(
            first.text,
            maximumConcurrentThreadsPerSession: 11,
            state: first.state
        )

        #expect(second.state.originalValue == 9)
        #expect(second.state.lastManagedValue == 11)
        #expect(
            try CodexAgentConcurrencyEditor.restoring(second.text, state: second.state)
                == original
        )
    }

    @Test("Restoration preserves value and syntax drift")
    func driftPreservation() throws {
        let dotted = try CodexAgentConcurrencyEditor.activating(
            "agents.role_count = 2",
            maximumConcurrentThreadsPerSession: 7
        )
        let valueDrift = dotted.text.replacingOccurrences(of: " = 7", with: " = 8")
        #expect(
            try CodexAgentConcurrencyEditor.restoring(valueDrift, state: dotted.state)
                == valueDrift
        )

        let syntaxDrift = "[agents]\nmax_concurrent_threads_per_session = 7"
        #expect(
            try CodexAgentConcurrencyEditor.restoring(syntaxDrift, state: dotted.state)
                == syntaxDrift
        )
    }

    @Test("Restoration preserves valid TOML that drifted to an unmanaged value or form")
    func unmanagedDriftPreservation() throws {
        let edit = try CodexAgentConcurrencyEditor.activating(
            "agents.max_depth = 2",
            maximumConcurrentThreadsPerSession: 7
        )
        for drift in [
            "agents.max_concurrent_threads_per_session = \"manual\"",
            "agents.max_concurrent_threads_per_session = 7.5",
            "agents.max_concurrent_threads_per_session = false",
            "agents = { max_concurrent_threads_per_session = 7 }",
        ] {
            #expect(
                try CodexAgentConcurrencyEditor.restoring(drift, state: edit.state)
                    == drift
            )
        }
    }

    @Test("Inline tables, unsupported agents values, and the legacy alias are rejected")
    func refusedAgentsForms() {
        #expect(throws: CodexAgentConcurrencyEditor.Error.inlineAgentsTable) {
            try CodexAgentConcurrencyEditor.activating(
                "agents = { role = \"worker\" }",
                maximumConcurrentThreadsPerSession: 4
            )
        }
        #expect(throws: CodexAgentConcurrencyEditor.Error.unsupportedAgentsSyntax) {
            try CodexAgentConcurrencyEditor.activating(
                "agents = \"worker\"",
                maximumConcurrentThreadsPerSession: 4
            )
        }
        for text in [
            "agents.max_threads = 2",
            "[agents]\nmax_threads = 2",
            "[agents]\nmax_threads = 2\nmax_concurrent_threads_per_session = 3",
        ] {
            #expect(throws: CodexAgentConcurrencyEditor.Error.legacyAlias) {
                try CodexAgentConcurrencyEditor.activating(
                    text,
                    maximumConcurrentThreadsPerSession: 4
                )
            }
        }
    }

    @Test("String, float, and Boolean managed values are rejected")
    func nonIntegerValues() {
        for text in [
            "agents.max_concurrent_threads_per_session = \"4\"",
            "agents.max_concurrent_threads_per_session = 4.0",
            "agents.max_concurrent_threads_per_session = true",
        ] {
            #expect(throws: CodexAgentConcurrencyEditor.Error.nonIntegerManagedValue) {
                try CodexAgentConcurrencyEditor.activating(
                    text,
                    maximumConcurrentThreadsPerSession: 4
                )
            }
        }
    }

    @Test("Duplicate and conflicting canonical assignments are rejected")
    func duplicateAndConflictingAssignments() {
        for text in [
            "[agents]\nmax_concurrent_threads_per_session = 3\nmax_concurrent_threads_per_session = 4",
            "agents.max_concurrent_threads_per_session = 3\n[agents]\nmax_concurrent_threads_per_session = 4",
        ] {
            #expect(throws: (any Swift.Error).self) {
                try CodexAgentConcurrencyEditor.activating(
                    text,
                    maximumConcurrentThreadsPerSession: 4
                )
            }
        }
    }

    @Test("Malformed input is rejected before editing")
    func malformedInput() {
        #expect(throws: (any Swift.Error).self) {
            try CodexAgentConcurrencyEditor.activating(
                "agents = [",
                maximumConcurrentThreadsPerSession: 4
            )
        }
    }
}

extension CodexAgentConcurrencyEditorTests {
    @Test("Restoration is fail-safe when a journal lost its original token")
    func missingOriginalTokenIsPreserved() throws {
        let managed = "[agents]\nmax_concurrent_threads_per_session = 4"
        let state = CodexAgentConcurrencyState(
            originalWasPresent: true,
            originalValue: 8,
            originalSyntax: .canonical,
            originalToken: nil,
            createdAgentsTable: false,
            lastManagedValue: 4,
            managedSyntax: .canonical
        )

        #expect(try CodexAgentConcurrencyEditor.restoring(managed, state: state) == managed)
    }

    @Test("Quoted managed keys are rejected because their source form cannot be preserved")
    func quotedManagedKeyIsRejected() {
        #expect(throws: CodexAgentConcurrencyEditor.Error.unsupportedManagedSyntax) {
            try CodexAgentConcurrencyEditor.activating(
                "[agents]\n\"max_concurrent_threads_per_session\" = 4",
                maximumConcurrentThreadsPerSession: 3
            )
        }
    }

    @Test("Insertion precedes trailing section whitespace and accepts array tables")
    func insertionBoundaries() throws {
        let sectioned = "[agents]\nrole = \"worker\"\n\n[features]\nenabled = true"
        let inserted = try CodexAgentConcurrencyEditor.activating(
            sectioned,
            maximumConcurrentThreadsPerSession: 3
        )
        #expect(
            inserted.text
                == "[agents]\nrole = \"worker\"\nmax_concurrent_threads_per_session = 3\n\n[features]\nenabled = true"
        )

        let arrayTable = "[[workers]]\nname = \"reviewer\""
        let created = try CodexAgentConcurrencyEditor.activating(
            arrayTable,
            maximumConcurrentThreadsPerSession: 2
        )
        #expect(created.text.hasSuffix("[agents]\nmax_concurrent_threads_per_session = 2"))
    }

    @Test("Cleanup tolerates a legacy dotted journal that claimed a created table")
    func cleanupWithoutOwnedHeader() throws {
        let managed = "agents.max_concurrent_threads_per_session = 4\napproval_policy = \"on-request\""
        let state = CodexAgentConcurrencyState(
            originalWasPresent: false,
            originalValue: nil,
            originalSyntax: nil,
            originalToken: nil,
            createdAgentsTable: true,
            lastManagedValue: 4,
            managedSyntax: .dotted
        )

        #expect(
            try CodexAgentConcurrencyEditor.restoring(managed, state: state)
                == "approval_policy = \"on-request\""
        )
    }
}
