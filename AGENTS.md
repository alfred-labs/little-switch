# Repository Guidelines

LittleSwitch is a native Apple Silicon macOS menu-bar application. One Swift
process owns the AppKit/SwiftUI interface, the Claude profile transaction, and the
Anthropic-compatible gateway on `127.0.0.1:11436`.

## Working Agreement

- Treat the working tree as shared and potentially dirty. Run `git status --short`
  before editing, preserve unrelated user changes, and keep every changed line
  traceable to the requested scope.
- Do not use `git reset`, `git checkout --`, destructive cleanup, or broad
  formatting commands. Do not create a worktree unless the user explicitly asks
  for one.
- Prefer `rg` and `rg --files` for discovery, `apply_patch` for edits, and `mise`
  tasks for repository commands.
- Never commit, stage, relaunch apps, interrupt Claude, or change persistent user
  state unless the user authorized that action for the current task.
- Keep temporary probes out of the final diff. Remove them with `apply_patch` and
  verify their names no longer occur before handoff.

## Architecture Boundaries

- `Sources/LittleSwitchTransport` owns outbound HTTP, URL assembly, SSE framing,
  and Zstandard. It must not depend on Core, Search, SwiftUI, or AppKit.
- `Sources/LittleSwitchSearch` owns the common search contract, configuration,
  and provider adapters. It depends on Transport, never Core or Keychain.
- `Sources/LittleSwitchCore` owns deterministic domain, routing, gateway,
  protocol adapters, persistence, and security policy. It consumes Search and
  Transport and must not depend on SwiftUI or AppKit.
- `Sources/LittleSwitchUI` owns AppKit lifecycle, SwiftUI presentation, Claude
  application control, and UI-facing state.
- `ApplicationCoordinator` is the authority for mutable product state. `AppModel`
  is `@MainActor` presentation state; views dispatch intent and do not become a
  second source of truth.
- Preserve Swift 6 strict concurrency. Prefer actors, immutable snapshots,
  structured tasks, explicit `Sendable` boundaries, and exhaustive enums over
  locks, detached work, ambiguous booleans, or unchecked isolation.
- Keep the gateway protocol-transparent unless an explicitly designed adapter,
  such as the bounded web-search bridge (Firecrawl, Tavily, Brave), owns the
  conversion.

## Implementation Rules

- Always favor the highest-quality implementation over the smallest diff. A
  larger refactor is acceptable, and preferred, when it buys a materially
  better result (user directive, 2026-09-01: "toujours privilégier les
  implémentations de qualité").
- Start behavior changes with a focused failing Swift Testing test. Keep tests
  beside the owning target and compare complete values when practical.
- Prefer small, single-purpose files. Extract a focused unit instead of growing a
  central coordinator or view past easy review.
- Use native SwiftUI and AppKit controls before custom drawing. Follow
  [`docs/product-design.md`](docs/product-design.md) for every layout, copy,
  density, icon, color, or interaction decision.
- Store credentials only through `SecretStore`/Keychain. Never print, snapshot,
  persist, or place secrets in command arguments. Treat `.env`, traffic bodies,
  provider headers, and Claude content as sensitive.
- Do not weaken production behavior or tests to accommodate the managed sandbox.
  A loopback `EPERM` or `Operation not permitted` requires a narrowly escalated
  rerun of the affected command, not a code workaround.

## Verification Ladder

During implementation, run the smallest test or strict build that exercises the
change. Before handing off runtime changes, run:

```sh
mise run check
```

This is the authoritative automated gate: format, SwiftLint, strict builds, Swift
Testing, exact core coverage, Thread Sanitizer, repository policies, release build,
app bundle build, and bundle verification.

`mise run check 2>&1 | tail -N` reports `tail`'s exit code, never the gate's —
a failed gate piped through `tail` still looks like success. Read the full
text or drop the pipe.

Run gate tasks through mise (`mise run swift:coverage`), never as
`./tools/ci/*.sh` directly. `xcode-select` points at the CommandLineTools,
whose toolchain lacks the swift-testing module for the classic `--no-parallel`
build, so direct invocations fail with `no such module 'Testing'`; mise's
`DEVELOPER_DIR` pin in `.mise.toml` selects full Xcode and is the only
supported environment.

For documentation-only changes, do not spend time on the full Swift suite. Run
scoped link/content checks plus `git diff --check`, and state that the runtime gate
was skipped because executable code did not change.

Automated tests are necessary but insufficient for user-visible work. Any change
to layout, copy, controls, menus, windows, dialogs, navigation, focus, loading,
errors, or interaction must also pass the mandatory real-app protocol in
[`docs/computer-use-validation.md`](docs/computer-use-validation.md). Do not claim a
UI change is complete from compilation, unit tests, or source inspection alone.

## Real-App Safety

- Never restart LittleSwitch or kill anything on `127.0.0.1:11436` while a
  session routes through the gateway — it terminates that session. The user
  relaunches the app themselves.
- Replay diagnostics: the original client body is recorded base64 in
  `claudeRequestBody` actions under
  `~/Library/Application Support/LittleSwitch/Logs/*.jsonl`. Retention is
  roughly 30 minutes, so read promptly; replaying a recorded body through
  the live gateway reproduces failures deterministically.
- Validate the freshly built `build/LittleSwitch.app`, never an older process.
- After every redeploy (rebuild plus relaunch), verify the running build tag:
  `curl -s http://127.0.0.1:11436/api/about` must report the current
  `git describe --tags --always --dirty`. A mismatch or `development` means a
  stale bundle was launched — rebuild and relaunch again before testing. The
  bundle binary's modification time is not sufficient proof.
- Run exactly one LittleSwitch instance. Resolve stale processes and port owners
  before testing, while preserving the user's initial application state.
- Use Computer Use through `node_repl` and `@oai/sky`; inspect fresh application
  state after every action and never reuse stale accessibility element indices.
- Authentication, Keychain unlock, credentials, and unexpected permission prompts
  require user handoff. Never type or reveal a secret. If the user is unavailable,
  stop instead of repeatedly relaunching the app.
- A screenshot is visual evidence, not protocol evidence. For example, Claude's
  generic “Web searched” UI does not prove Firecrawl ran; corroborate it with the
  gateway trace and response structure required by the validation guide.

## Completion

- Review the scoped diff and `git status --short`; mention any unrelated dirty
  files without modifying them.
- Report the exact commands and real-app scenarios that passed. If a required gate
  was not run or a prompt blocked validation, say so plainly.
- Leave the application, Claude, configuration, selected section, and temporary
  artifacts in the state agreed with the user.
