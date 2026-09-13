# Official SDK contracts

This tool extracts Draft 7 schemas from the exact TypeScript SDK versions in
`package.json` and `package-lock.json`. It parses type-only declarations without
loading either SDK client. Node 24.16.0 (Krypton LTS) is pinned by each mise task.

```sh
mise run schemas:install
mise run schemas:test
mise run schemas:extract
mise run schemas:upstream:check
```

Installation is explicit and disables npm lifecycle scripts. Tests, extraction,
comparison, and verification never install packages. Commit the lockfile; it
records transitive versions and npm integrity hashes.
Extraction also checks the installed TypeScript package and loaded compiler
against the lock before generating anything; provenance records that verified
compiler version. A stale installation must be repaired with the explicit
installation task.

`schemas/roots.json` binds each local type alias to its SDK, module, exported type,
and schema path. Extraction verifies these bindings against the TypeScript AST.
`schemas/sdk-sources.json` records exact source versions and licenses. Generated
`schemas/upstream/manifest.json` records root declaration hashes, extraction input
hashes, generator options, copied license notices, and every artifact's SHA-256.
All paths are relative; generated files contain no extraction timestamp. Never
patch files inside `schemas/upstream` manually.

Initial extraction requires an absent or empty output directory. Output paths,
including the root and its ancestors, must be physical paths without symbolic
links. The tools resolve the operating system's temporary-directory alias before
creating temporary snapshots; use a physical path for custom extraction output.
An explicit `schemas:extract` can restore missing manifest-owned artifacts, but
validates the old manifest, every remaining artifact hash, and the remaining file
tree before writing. Unowned files, conflicting paths, and non-regular files stop
extraction. Repair retains the old ownership list so retired artifacts are still
removed, and the new manifest is published after artifact writes and removals.

The catalogue retains `root`, owning `definition`, and schema JSON Pointer `path`
for every property and closed enum. Property entries contain `key`, `required`,
and `nullable`. Enum `values` are JSON scalars. A referenced or nullable enum is
also resolved at its property's path, so consumers join by `root` and `path`.
Open string unions are not represented as closed enums. Recursive references are
kept in the schemas without expanding them into an infinite property tree.

Objects remain open to extra properties unless an extracted index signature
constrains their values. These schemas characterize the TypeScript declarations,
not all API business rules: fractional `max_tokens` is accepted, while Chat's
provider-specific finish reason `sensitive` is rejected. Anthropic requests reject
`stream: null`; OpenAI Responses and Chat accept it. All three accept absent,
false, and true according to their full SDK request union. `PresenceProbe` is a
separate local fixture, excluded from the official catalogue.

For an intentional SDK upgrade, edit exact versions in the package and source
manifests, regenerate the lock with lifecycle scripts disabled, then explicitly
run `schemas:install`. Capture the changes with:

```sh
mise run schemas:update > /tmp/sdk-contract-changes.json
```

Update requires an existing snapshot with valid hashes, keeps a temporary copy,
extracts the installed exact versions, and reports changes as JSON on stdout.
It never resolves a latest version or runs installation. Initial bootstrapping
uses `schemas:extract`. Inspect the report before the separate Swift generation
step. A snapshot verification error stops update before any repository write.

To compare two retained snapshot directories independently:

```sh
mise run schemas:compare -- /path/to/old/upstream /path/to/new/upstream
```

The JSON report classifies schema/property additions and removals, required and
nullable changes, and closed enum/value changes. Every other schema byte change
is still reported as `schema-changed`; the report is not an automatic verdict on
API compatibility. Both snapshots' bytes are verified before parsing their
schemas and catalogue. `schemas:upstream:check` also compares against a fresh
extraction in a temporary directory and never repairs the checkout.
