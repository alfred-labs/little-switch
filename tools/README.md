# LittleSwitch repository tooling

`LittleSwitchTooling` is a standalone Swift 6 package targeting macOS 14. Its
`RepositoryTooling` target owns testable repository rules. The
`littleswitch-tools` executable adapts command arguments and file I/O using
Apple's Swift Argument Parser. SwiftSyntax parses source for repository policies
and the string scanners.

Run commands through mise from the repository so they inherit the pinned Xcode
environment and use a tooling build directory independent of the application:

```sh
mise run tools:build
mise run tools:test -- --filter ConventionalCommit
mise run tools:deadcode
mise run tools:coverage
mise run tools:run -- repo commit-message ".git/COMMIT_EDITMSG"
mise run tools:run -- repo check
mise run --quiet tools:run repo ui-strings
mise run tools:run -- coverage scope --measured
mise run tools:run -- release --help
mise run diagnostics:session-tools -- "/path/to/Logs" --mounted 20
```

The executable accepts `--root <directory>` at any command level. Relative
message paths resolve against that root; without the option, they resolve from
the invocation directory. Absolute message paths remain absolute. The mise
`tools:run` task supplies the repository root explicitly.

```sh
littleswitch-tools --root "/path/to/little-switch" repo commit-message "commit message.txt"
littleswitch-tools repo commit-message --help
```

Commit validation reads the first nonblank, noncomment line. It accepts the
existing Conventional Commit types and Git-generated merge, revert, fixup, and
squash subjects. Success exits with status zero and no output. Invalid messages,
unreadable files, and argument errors exit nonzero with diagnostics on stderr;
explicit help is printed on stdout.

`repo check` validates product identity, brand assets, bundle icon metadata, UI
localization and the architecture boundaries recorded by the repository policies.
The tests also exercise actual ICNS generation with the Apple tools.

`repo ui-strings [directory]` rejects unlocalized literals in known SwiftUI, AppKit
and settings presentation APIs. The default directory is `Sources/LittleSwitchUI`.
Findings include the file, line, column and static segments of interpolated
strings, sorted in source order. Empty literals are ignored. Nested presentation
calls, such as a text field's `Text` prompt, report each literal once.

The scanner follows direct literals, ternary results, concatenation, nil
coalescing, parentheses and casts. Function calls are opaque: arguments to
`L10n.resource`, `L10n.string`, Foundation localization APIs and other helpers
are not treated as untranslated display text. Conditions, image names and
unrelated argument labels are also ignored. This is a syntax inventory, with no
type inference or tracking of variables, aliases and helper return values.

`Text(verbatim:)` explicitly marks a value as intentionally nonlocalized and is
exempt, including qualified `SwiftUI.Text(verbatim:)` calls. This exemption does
not cover adjacent help or accessibility text. Use the existing
`ProductIdentity.displayName` for the product name. Plain `Text("Settings")` still
fails; use `Text(L10n.resource("Settings"))` for translated copy. There is no
blanket exemption for particular string values and no baseline to refresh.

The command exits zero when there are no findings and exits one after printing
any findings. `repo check` applies the same rules to `Sources/LittleSwitchUI`, so
`mise run check` blocks on new unlocalized UI literals. Missing paths, file roots
and read errors exit nonzero without printing a partial inventory. A linked root
is resolved, while symbolic links inside the scanned directory are skipped.

`coverage scope` recursively classifies production Swift files using the reviewed
exclusion TSV. `coverage verify --measured-list <path> --report <path>` requires
one report row per measured source, valid integer line counts, no missed lines,
the exact displayed percentage and a TOTAL equal to the sum of measured lines.
`--raw-report <path>` additionally checks the raw linked-source report for LLVM
warnings and a unique total. The app and tooling use separate coverage builds;
named system adapters and declaration-only files have explicit justifications.

`release bump`, `release appcast` and `release homebrew` own version validation,
Sparkle XML, published artifact checks and cask generation. The `release:*` mise
tasks retain the ordered shell calls to Apple signing and notarization tools,
Git and GitHub. Integration fixtures exercise these calls against temporary
repositories and synthetic artifacts.

Application bundle assembly shortens Sparkle's ordinary update announcement in
English (`Base`) and French using `sparkle-update-copy.sh`. Only the copied
framework resources are changed, before signing; the SwiftPM artifact remains
untouched. Development builds reseal the framework with an ad-hoc signature when
no Developer ID is configured. Bundle verification checks the customized text.
A missing upstream string key fails the build so Sparkle upgrades require review
rather than silently restoring the original announcement.

For an explicitly started local Prometheus/Loki lab, `mise run monitoring:readiness`
waits for both services and `mise run monitoring:probe` inserts synthetic OTLP JSON,
then verifies the matching metric and log through their query APIs. The separate
`monitoring:integration` task exercises the application's exporter. See the
[monitoring guide](../docs/monitoring.md) for lab setup.

`diagnostics session-tool-defs <logs-directory> [--mounted N]` streams selected
`traffic-*.jsonl` segments in modification order. It reports request count, the
last and peak inline MCP definition counts, and presence of ToolSearch. Grouping
uses the model, the first 400 characters of sorted ASCII-escaped first-message
JSON, and builtin tool names; matching conversations can therefore merge into
one row. These groups are not session identifiers. Output contains only aggregate
metrics. `--mounted N` uses the known mounted count as the ratio denominator.

The Git hook invokes the Swift validator through mise, preserving SwiftPM's build
freshness checks. Installing this repository does not change Git's configured hook
path. Node/npm and Python are not required by these repository workflows.
The application package and its dependency graph are independent of this package.
