# Developer Guide

This guide covers building, verifying, and contributing to LittleSwitch. For product behavior and user-facing docs, see the [README](README.md).

## Prerequisites

- macOS 14 or later
- Xcode 26.6 with Swift 6.3.3 (license accepted)
- [mise](https://mise.jdx.dev/)

## Build

```sh
mise install
mise run check
mise run build
open "build/LittleSwitch.app"
```

`mise run check` is the authoritative quality gate. It runs format, SwiftLint, strict builds, Swift Testing, exact core coverage, Thread Sanitizer, repository policies, release build, app bundle build, and bundle verification. A failed gate piped through `tail` still looks like success: read the full output or drop the pipe.

`mise run build` produces an unsigned arm64 Apple Silicon app. To codesign locally, set `LITTLE_SWITCH_SIGN_IDENTITY` to your desired identity before building.

## Architecture

LittleSwitch is a single Swift process that owns the AppKit/SwiftUI interface, the Claude profile transaction, and the Anthropic-compatible gateway on `127.0.0.1:11436`.

### Module boundaries

- **`Sources/LittleSwitchTransport`** owns outbound HTTP, URL assembly, SSE framing, and Zstandard. It must not depend on Core, Search, SwiftUI, or AppKit.
- **`Sources/LittleSwitchSearch`** owns the common search contract, configuration, and provider adapters. It depends on Transport, never Core or Keychain.
- **`Sources/LittleSwitchCore`** owns deterministic domain, routing, gateway, protocol adapters, persistence, and security policy. It consumes Search and Transport. It must not depend on SwiftUI or AppKit.
- **`Sources/LittleSwitchUI`** owns AppKit lifecycle, SwiftUI presentation, Claude application control, and UI-facing state.
- **`ApplicationCoordinator`** is the authority for mutable product state. `AppModel` is `@MainActor` presentation state. Views dispatch intent and do not become a second source of truth.

### Concurrency

Preserve Swift 6 strict concurrency. Prefer actors, immutable snapshots, and exhaustive enums. Avoid locks, detached work, and unchecked isolation.

Keep the gateway protocol-transparent unless an explicitly designed adapter (such as the bounded web-search bridge for Firecrawl, Tavily, Brave, or Exa) owns the conversion.

## Implementation rules

- Start behavior changes with a focused failing Swift Testing test. Keep tests beside the owning target and compare complete values when practical.
- Prefer small, single-purpose files. Extract a focused unit instead of growing a central coordinator or view past easy review.
- Use native SwiftUI and AppKit controls before custom drawing.
- Store credentials only through `SecretStore`/Keychain. Never print, snapshot, persist, or place secrets in command arguments. Treat `.env`, traffic bodies, provider headers, and Claude content as sensitive.
- Do not weaken production behavior or tests to accommodate the managed sandbox. A loopback `EPERM` or `Operation not permitted` requires a narrowly escalated rerun of the affected command, not a code workaround.

## Design docs

- [Product design](docs/product-design.md), layout, copy, density, icon, color, and interaction decisions
- [Styleguide](docs/styleguide.md), shared native styling, typography, controls, and visual-asset provenance

## Technical docs

- [Architecture](docs/architecture.md): module boundaries, compilation targets, and service contracts
- [Provider request queue](docs/provider-request-queue.md), FIFO capacity, native client limits, and monitoring
- [Monitoring](docs/monitoring.md), metrics, logs, and OTLP export
- [Known limitations](docs/known-limitations.md), documented boundaries and edge cases

## Release

You publish releases directly from this repository. The DMG is notarized and attached to a GitHub Release, and the Sparkle appcast lives in `packaging/appcast.xml`.

```sh
mise run release:bump
mise run release:dmg
mise run release:notarize
mise run release:verify
mise run release:publish -- --push
```

`release:publish -- --push` creates the GitHub Release, commits the appcast, and updates the Homebrew cask in one step. Without `--push`, everything is committed locally for review.

## License

LittleSwitch is licensed under the [Business Source License 1.1](LICENSE) (BSL 1.1). Contributions are welcome and remain under the same license.
