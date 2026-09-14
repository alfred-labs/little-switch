import Foundation

/// The installed Claude Code CLI version, used to decide when the
/// tool-search non-regression probe must re-run (spec §7 test 3): the
/// design depends on CLI internals that can regress silently.
public struct ClaudeCodeCLIVersion: Equatable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Parses `<version>` from `claude --version` output. Observed shapes:
    /// `"2.1.259 (Claude Code)"`, `"2.1.259"`.
    public init?(parsing output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = trimmed.split(whereSeparator: \.isWhitespace).first,
            !token.isEmpty
        else {
            return nil
        }
        self.rawValue = String(token)
    }

    /// First run, or any change from the last validated version.
    public func requiresRevalidation(
        previouslyValidated: ClaudeCodeCLIVersion?
    ) -> Bool {
        previouslyValidated != self
    }
}
