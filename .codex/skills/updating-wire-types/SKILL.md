---
name: updating-wire-types
description: Use when upgrading LittleSwitch's official OpenAI or Anthropic SDK contracts, comparing upstream schema changes, regenerating LittleSwitchWire, or investigating contract drift. Excludes changing provider models, credentials, and transport settings.
---

# Updating Wire Types

`LittleSwitchWire` is derived from exact-pinned official TypeScript SDKs. Generated
Swift files and upstream snapshots are outputs; fix their inputs or the generator.
Read `schemas/sdk-sources.json`, `schemas/roots.json`, `schemas/projections.json`,
`schemas/compatibility.json` and the relevant mise task definitions first.

An audit or comparison request is read-only. An upgrade request authorizes changing
the requested SDK inputs and generated contracts in the agreed worktree. Preserve
unrelated changes and the original stash; follow the repository's Git rules.

## Compare

Two complete snapshot directories are needed. Each includes `manifest.json`, its
catalogue and every artifact named by the manifest. Do not compare catalogues
alone: constraints outside the catalogue can also change.

```sh
mise run --quiet schemas:compare -- /absolute/path/to/previous/upstream schemas/upstream
```

Report old/new SDK versions, changed roots and JSON Pointers, required/nullable
changes, enum additions/removals, other schema changes, and affected Swift consumers.
A `schema-changed` result requires inspecting that schema's diff; it is not a
compatibility verdict. A new enum case may break an exhaustive Swift switch.

## Upgrade

1. Resolve the requested version from the official SDK release and verify its
   identity. Use exact versions in `tools/sdk-contracts/package.json` and
   `schemas/sdk-sources.json`. Update only the requested SDK. Refresh the lock with
   the Node version pinned by the mise tasks and installation scripts disabled;
   inspect changes to transitive dependencies. `schemas:install` uses `npm ci`:
   it installs an existing lock, it does not update that lock.
2. Run `mise run schemas:install`, then `mise run schemas:test`.
3. Run `mise run --quiet schemas:update` to regenerate upstream contracts and
   produce the comparison. Preserve the report in the agreed review artifact.
   This command does not choose versions or install dependencies. If the previous
   snapshot fails integrity checks, diagnose the failure before replacing it.
   Review changes to the SDK notices too; the bundle copies their exact snapshot
   texts, and `verify:bundle` checks that they match.
4. Review every affected projection and named compatibility adaptation. Add a
   fixture for changed behavior before changing its implementation. Regenerate
   with `mise run schemas:generate`; keep generated files unedited.
5. Run `mise run schemas:check`, focused Wire/adapter tests, then `mise run check`.
   Include `GeneratedWireQualificationTests`: its samples regenerate with each
   projected declaration and assert complete JSON or exact diagnostics. Keep the
   manual compatibility and authorization tests alongside that generated evidence.
   An automatic qualification limit means the bounded sample search could not
   find a witness; inspect the reported source pointer and add a regression before
   extending that search. It is not evidence that the upstream schema is invalid.
   Review the two retained `WireCodingError` public properties documented in
   `.periphery.yml`; their baseline entries identify symbols, not warning kinds,
   so they need manual API review if the diagnostic contract changes.
   Report exact versions, changes, commands and unresolved failures.

For a deliberate first bootstrap only, use `schemas:extract` instead of updating
an absent previous snapshot. Use mise for the pinned Node and Xcode environments.

## JSON Runtime Maintenance

OrderedJSON is pinned separately under `Vendor/OrderedJSON`. Follow its README
when comparing an upstream release or updating its local patches. Review original
source hashes, the exact patch, the complete fixture corpus, and changed runtime
paths. Run `mise run ordered-json:check`, `mise run ordered-json:tools:test`, and
`mise run ordered-json:test`, then the Wire and application gates. Repeat the
release comparison on the same synthetic history, tools and event fixtures when
changing parsing or encoding. Keep exact numeric tokens, strict UTF-8, original
bytes, key order and duplicate-key semantics covered.

## Contract Decisions

- TypeScript shapes do not encode every API constraint. Check integer/range and
  provider-specific rules separately; extraction is Draft 7, not a runtime DSL.
- Keep missing and explicit null distinct. Preserve existing adapter normalizations
  and privacy filtering when updating the wire representation.
- A known discriminator with malformed content must fail. An unknown value kept
  for forwarding does not authorize a tool or make private fields public.
- Model IDs, tool names, namespaces and opaque tool schemas remain open data.
- Keep extensions in `schemas/compatibility.json` with source and fixture. Never
  silently weaken all required fields, broaden the scanner baseline, or exclude
  generated code from coverage to make an upgrade pass.
