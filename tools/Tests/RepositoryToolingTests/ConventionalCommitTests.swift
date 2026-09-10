import Testing

@testable import RepositoryTooling

@Suite("Conventional commit validation")
struct ConventionalCommitTests {
    @Test(
        "Conventional and generated Git subjects are accepted",
        arguments: [
            "feat(gateway): route Claude models",
            "fix!: change profile format",
            "chore(release): LittleSwitch v0.1.0",
            "Merge branch 'main'",
            "Revert \"feat: route models\"",
            "fixup! feat: route models",
            "squash! feat: route models",
            "feat: add routing",
            "fix: restore profile",
            "docs: describe setup",
            "style: format sources",
            "refactor: extract routing",
            "perf: reuse connections",
            "test: cover retries",
            "build: package application",
            "ci: verify bundle",
            "chore: maintain tooling",
            "revert: undo routing",
            "feat(provider/api)!: change protocol",
            "feat( ): preserve the existing scope grammar",
            "feat: preserve\u{0085}the existing subject grammar",
            "Merge \u{0301}branch",
            "Revert \"\u{0301}subject\"",
            "fixup! \u{0301}subject",
            "squash! \u{0301}subject",
        ]
    )
    func acceptedSubject(subject: String) {
        #expect(ConventionalCommit.validate(subject) == .success(subject))
    }

    @Test(
        "Invalid and unknown subjects are rejected",
        arguments: [
            "Release 0.1.0",
            "feature: route models",
            "feat route models",
            "Feat: route models",
            "feat(): route models",
            "feat(nested(scope)): route models",
            "feat:route models",
            "feat:",
            "feat!!: route models",
            "merge branch 'main'",
            "Revert feat: route models",
            "fixup!feat: route models",
            "squash!feat: route models",
            "feat: split\rsubject",
            "feat: split\u{2028}subject",
            "feat: split\u{2029}subject",
            "\u{0085}feat: preserve the existing trim grammar",
            "",
        ]
    )
    func rejectedSubject(subject: String) {
        #expect(ConventionalCommit.validate(subject) == .failure(.invalidSubject(subject)))
    }

    @Test(
        "Blank lines and comments are skipped before the trimmed subject",
        arguments: [
            "\n# Git comment\n\n  feat(gateway): route Claude models  \n\nBody text",
            "\r\n  # Git comment\r\n\tfeat(gateway): route Claude models\t\r\n",
            "\u{FEFF}feat(gateway): route Claude models\u{FEFF}",
            "#\u{0301}comment\nfeat(gateway): route Claude models",
        ]
    )
    func firstUsefulLine(message: String) {
        #expect(ConventionalCommit.validate(message) == .success("feat(gateway): route Claude models"))
    }

    @Test("Only the first useful line is validated")
    func invalidFirstLine() {
        #expect(
            ConventionalCommit.validate("\n# Comment\n  Invalid subject  \nfeat: valid later line")
                == .failure(.invalidSubject("Invalid subject")))
    }

    @Test(
        "Messages containing only whitespace and comments are empty",
        arguments: ["", " \t\n\r\n", "# Comment\n  # Other comment\n"])
    func emptyMessage(message: String) {
        #expect(ConventionalCommit.validate(message) == .failure(.invalidSubject("")))
    }
}
