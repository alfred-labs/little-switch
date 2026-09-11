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
                return try decoded(data, configText: configText)
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

        // Without a journal, legacy-managed roots cannot be treated as user
        // state. That profile never owned openai_base_url, whose captured
        // value must survive migration.
        if try CodexTOMLEditor.rootIsLegacyManaged(
            configText,
            catalogPath: paths.catalog.path
        ) {
            for key in CodexTOMLEditor.managedRootKeys where key != "profile" && key != "openai_base_url" {
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

    /// Journals written before native cohabitation never managed
    /// `openai_base_url`, so its current value is still user state. Capture it
    /// before activation or direct restoration can overwrite it. `web_search`
    /// keeps its separate nil-means-capture semantics and is never filled here.
    static func decoded(_ data: Data, configText: String) throws -> CodexProfileRestoreState {
        var state = try JSONDecoder().decode(CodexProfileRestoreState.self, from: data)
        if state.rootValues["openai_base_url"] == nil {
            state.rootValues["openai_base_url"] = try CodexTOMLEditor.rootState(
                "openai_base_url", in: configText
            )
        }
        return state
    }
}
