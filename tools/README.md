# LittleSwitch repository tooling

`LittleSwitchTooling` is a standalone Swift 6 package targeting macOS 14. Its
`RepositoryTooling` target owns testable repository rules. The
`littleswitch-tools` executable adapts command arguments and file I/O using
Apple's Swift Argument Parser, the package's only external dependency.

Run commands through mise from the repository so they inherit the pinned Xcode
environment and use a tooling build directory independent of the application:

```sh
mise run tools:build
mise run tools:test -- --filter ConventionalCommit
mise run tools:deadcode
mise run tools:coverage
mise run tools:run -- repo commit-message ".git/COMMIT_EDITMSG"
mise run tools:run -- repo check
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

`repo check` validates product identity, brand assets, bundle icon metadata and
the architecture boundaries recorded by the repository policies. The tests also
exercise actual ICNS generation with the Apple tools.

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
