import Foundation

/// Reads and upgrades the profile journal shared by the native and pre-native
/// LittleSwitch Codex profiles.
enum CodexProfileLegacyJournal {
    static func state(
        configText: String,
        configExisted: Bool,
        paths: CodexProfilePaths,
        fileStore: any CodexProfileFileStore
    ) throws -> CodexProfileRestoreState {
        if let data = try fileStore.snapshot(paths.restoreState) {
            let isManaged = try CodexTOMLEditor.rootIsManaged(
                configText,
                catalogPath: paths.catalog.path
            )
            let isLegacyManaged = try CodexTOMLEditor.rootIsLegacyManaged(
                configText,
                catalogPath: paths.catalog.path
            )
            if isManaged || isLegacyManaged {
                return try decoded(data)
            }
        }

        var state = CodexProfileRestoreState(
            configExisted: configExisted,
            rootValues: try Dictionary(
                uniqueKeysWithValues: CodexTOMLEditor.journaledRootKeys.map { key in
                    (
                        key,
                        try CodexTOMLEditor.rootState(
                            key, in: configText, preservingAssignment: key == "web_search"
                        )
                    )
                }
            ),
            agentConcurrency: nil
        )

        // Without a journal, the only safe interpretation of a legacy
        // LittleSwitch profile is that every managed root was not user state.
        if try CodexTOMLEditor.rootIsLegacyManaged(
            configText,
            catalogPath: paths.catalog.path
        ) {
            for key in CodexTOMLEditor.managedRootKeys where key != "profile" {
                state.rootValues[key] = CodexRootStringState(wasPresent: false, value: "")
            }
        }

        // The native profile is in the same position: a missing journal means
        // nothing proves the managed roots predate LittleSwitch — they may
        // simply have drifted while managed. Capturing them verbatim would
        // poison every later restore into re-applying the gateway wiring and
        // keeping the catalog referenced.
        if try CodexTOMLEditor.rootIsManaged(
            configText,
            catalogPath: paths.catalog.path
        ) {
            for key in CodexTOMLEditor.managedRootKeys where key != "profile" {
                state.rootValues[key] = CodexRootStringState(wasPresent: false, value: "")
            }
        }

        // A legacy LittleSwitch-owned provider root is not user state.
        if state.rootValues["model_provider"]?.value == CodexTOMLEditor.providerID {
            state.rootValues["model_provider"] = CodexRootStringState(
                wasPresent: false,
                value: ""
            )
        }

        return state
    }

    /// Journals written before native cohabitation predate
    /// `openai_base_url`: that key restores as absent. `web_search` keeps its
    /// nil-means-capture semantics and is never filled.
    static func decoded(_ data: Data) throws -> CodexProfileRestoreState {
        var state = try JSONDecoder().decode(CodexProfileRestoreState.self, from: data)
        for key in ["openai_base_url"] where state.rootValues[key] == nil {
            state.rootValues[key] = CodexRootStringState(wasPresent: false, value: "")
        }
        return state
    }
}
