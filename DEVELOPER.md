# Developer Guide

This guide covers building, verifying, and contributing to LittleSwitch. For product behavior and user-facing docs, see the [README](README.md).

## Prerequisites

- macOS 14 or later
- Xcode 27.0 with Swift 6.4 (license accepted)
- [mise](https://mise.jdx.dev/)

## Build

```sh
mise install
mise run schemas:install
mise run check
mise run build
open "build/LittleSwitch.app"
```

`mise run check` is the authoritative quality gate. It runs format, SwiftLint, strict builds, Swift Testing, exact core coverage, Thread Sanitizer, repository policies, release build, app bundle build, and bundle verification. A failed gate piped through `tail` still looks like success: read the full output or drop the pipe.

`mise run build` produces an unsigned arm64 Apple Silicon app. To codesign locally, set `LITTLE_SWITCH_SIGN_IDENTITY` to your desired identity before building.

Every release entry point (`swift:build`, `app:build`, `build`, and `release:dmg`)
uses `tools/swift-release.sh`. It pins the `swiftbuild` driver and the repository's
`.build` scratch directory; the current release products are in
`.build/out/Products/Release`. The assembler queries that same configuration with
`--show-bin-path`, then copies its executable and resource bundles into the single
application bundle, `build/LittleSwitch.app`. It never reads the legacy
`.build/arm64-apple-macosx/release` output or falls back to an older executable.

`mise run check` compiles the release once, as part of `app:build`.
`verify:bundle` compares the app's Mach-O UUID and resource bundles with that
release product, so a fresh Git tag cannot hide a stale executable. Coverage,
Thread Sanitizer, repository tooling and Periphery retain their test or analysis
builds; none of those products are eligible for application packaging.

`release:verify` runs the same executable and resource checks on the application
mounted from the final DMG, so a valid signature cannot hide missing resources.
The assembler also embeds the compatibility runtimes identified by Apple's
`swift-stdlib-tool` and signs them before the application. Bundle verification
requires these libraries even when the development machine already provides them.

## CI

The [CI workflow](.github/workflows/build.yml) runs on pushes and pull requests
targeting `main`, and can also be started manually from GitHub Actions. It installs
the pinned mise tools and schema dependencies, then runs the same `mise run check`
gate as local development: format, SwiftLint, repository and schema checks, Swift
tests, exact coverage, Periphery, Thread Sanitizer, release build, and bundle
verification. The release executable is compiled once, through `app:build`.
The checkout includes the complete Git history because the repository policies
validate the history of the committed magic-string baseline.

It uses GitHub's [Xcode 27 ARM64 preview image](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md),
which provides the Xcode version required by `mise run toolchains`.

### Dependency caches

Mise caches its pinned tools. SwiftPM's shared caches at `.build/cache` and
`.build/tooling-cache` retain downloaded repositories, binary artifacts, prebuilts,
and manifests across the separate test and analysis builds. Their cache key
includes the runner OS, architecture, exact Xcode build, and all three tracked
`Package.resolved` files. A changed lockfile can reuse a cache from the same
toolchain; SwiftPM still resolves the requested versions.

The schema tools cache npm's downloaded packages under
`.cache/sdk-contracts-npm/_cacache`, keyed by `tools/sdk-contracts/package-lock.json`.
`mise run schemas:install` always runs `npm ci`, including on cache hits.

Dependency caches are saved even when checks fail. Application and test build
products, coverage profiles, credentials, and `node_modules` are not cached, and
every quality check still runs on a cache hit. See the [GitHub caching strategies](https://github.com/actions/cache/blob/main/caching-strategies.md)
and [SwiftPM cache locations](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Workspace/Workspace%2BConfiguration.swift).

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
