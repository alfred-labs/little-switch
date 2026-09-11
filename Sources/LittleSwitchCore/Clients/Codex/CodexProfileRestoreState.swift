import Foundation

package struct CodexProfileRestoreState: Codable, Equatable, Sendable {
    var configExisted: Bool
    var rootValues: [String: CodexRootStringState]
    var agentConcurrency: CodexAgentConcurrencyState?
    /// The native catalog bytes merged into the managed catalog at activation
    /// time; status comparisons reuse them instead of re-probing Codex.
    var nativeCatalogData: Data?

    /// Capture a newly managed key before changing it. A legacy signature is
    /// also used by the coordinator to undo an upgrade after a save failure.
    mutating func preparingWebSearch(in text: String, mode: String?) throws -> String {
        if mode != nil {
            if rootValues["web_search"] == nil {
                rootValues["web_search"] = try CodexTOMLEditor.rootState(
                    "web_search", in: text, preservingAssignment: true
                )
            }
            return text
        }
        guard let original = rootValues.removeValue(forKey: "web_search") else {
            return text
        }
        return try CodexTOMLEditor.restoring(text, states: ["web_search": original])
    }

    func status(in text: String, expected: CodexManagedProfileSignature) -> CodexProfileStatus {
        var applied = expected
        if rootValues["web_search"] != nil {
            guard let mode = expected.webSearchMode,
                (try? CodexTOMLEditor.rootString("web_search", in: text)) == mode
            else {
                return .inactive
            }
        } else {
            applied = applied.withoutManagedWebSearch()
        }
        if let agentConcurrency {
            guard let maximum = expected.maximumConcurrentThreadsPerSession,
                maximum == agentConcurrency.lastManagedValue,
                let current = try? CodexAgentConcurrencyEditor.currentValue(in: text),
                current.value == maximum,
                current.syntax == agentConcurrency.managedSyntax
            else {
                return .inactive
            }
        } else {
            applied = applied.withoutNativeConcurrency()
        }
        return applied == expected ? .active(applied) : .requiresUpdate(applied)
    }
}
