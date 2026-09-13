# Swift wire generation

The official snapshots under `upstream/` come from the exact TypeScript SDK pins.
`projections.json` selects the contracts consumed by Swift; it is deliberately
smaller than the SDK catalogue. Run `mise run schemas:generate` after editing a
projection. `mise run schemas:check` verifies a fresh upstream extraction and
compares freshly generated Swift without repairing the checkout. Installation
remains the explicit `schemas:install` task.

## Using the Swift module

Import `LittleSwitchWire` and construct the generated values through their public
initializers. Literal tags are enums, and `WireCodec` handles their JSON form:

```swift
import LittleSwitchWire

let block = AnthropicTextParam(text: "Hello", type: .text)
let data = try WireCodec.encode(block)
let document = try WireCodec.decode(AnthropicTextParam.self, from: data)
let text = document.value.text
```

Forward `document.originalData` when no transformation is needed. Encode a
modified value explicitly with `WireCodec.encode`. `JSONPresence<T>` distinguishes
`.absent`, `.null`, and `.value(T)`; numeric properties use `JSONNumber` to retain
their exact literal. These codecs conform to `WireCodable`, whose JSON guarantees
are independent of Foundation's `Codable` representation.

The JSON value engine is the pinned OrderedJSON module under
[`Vendor/OrderedJSON`](../Vendor/OrderedJSON). Its local patches and upstream test
corpus are qualified separately; see that package's README for provenance and
updates. `WireCodec` validates UTF-8 before decoding and keeps diagnostics free of
payload values.

## Selecting a contract

Each entry in the version 1 `contracts` array accepts these fields:

| Field | Meaning |
| --- | --- |
| `root` | Exact root name from `roots.json`; identifies the official snapshot. |
| `pointer` | Schema JSON Pointer, default `#`; follows `$ref` aliases. |
| `swiftName` | Explicit public name for the selected root. |
| `fields` | Exact list of consumed wire keys retained from a selected record. Union branch records also retain their literal discriminators. |
| `branches` | Optional source indexes retained from a selected union. Indexes are validated and source order is preserved. |
| `opaque` | Optional absolute schema pointers explicitly represented as `JSONValue`. |
| `nodes` | Absolute source pointers mapped to `{ "name": "CompactName", "fields": [...], "branches": [...] }`; each option is optional. |
| `publicKeys` | Defaults to false. True exposes the source-derived `Key: String, CaseIterable, Sendable` on records in the selected graph for predecode normalization. |
| `output` | Defaults to `Sources/LittleSwitchWire/Generated`; the only other allowed root is `Tests/LittleSwitchWireTests/Generated`. |
| `schema` | Local schema path below `schemas/fixtures/`; allowed only for compiled test fixtures. Official contracts resolve through `roots.json`. |
| `importModule` | `LittleSwitchWire` for the separate compiled fixture target; omit for production output. |

For example, a consumer may select an existing SDK record and its consumed fields:

```json
{
  "root": "AnthropicMessage",
  "pointer": "#/definitions/Message",
  "swiftName": "AnthropicMessage",
  "fields": ["id", "content", "stop_reason", "usage"],
  "nodes": {
    "#/definitions/ContentBlock": {
      "name": "AnthropicContentBlock",
      "branches": [0, 1, 2]
    },
    "#/definitions/ThinkingBlock": {
      "name": "AnthropicThinkingBlock",
      "fields": ["thinking", "signature"]
    }
  }
}
```

Inspect the actual snapshot or `upstream/catalog.json` before choosing a pointer
or branch index. Root field selection is exact: an incoming message projection
can ignore `type`, `role`, and `model` without validating metadata that Core never
consumed. A selected tagged branch keeps its required discriminator even if that
key is omitted from `fields`. `nodes` gives consumed nested records compact names
and their own field/branch selections. `opaque` applies last. It cannot erase a
selected tagged branch or its discriminator, including through a reference.
An opaque envelope member can be decoded immediately
through a separately selected codec, avoiding duplicate declarations.

The selected root and reachable types are generated together. Inline and
referenced types receive contextual names such as `FixtureTaggedText` and
`FixtureTaggedTextType`. Definitions retain source identity within each graph;
two distinct `status` fields do not collapse into one enum. Separate projections
do not implicitly share names or declarations. Naming or output collisions fail.

Keys remain private by default. The explicit `publicKeys` option allows a Core
adapter to replace a source-defined field before decoding (for example, replacing
an upstream routing model while preserving every other value). The enum remains
scoped to its generated record; no global field namespace is introduced. A union
root can expose the keys of its selected variant records and their nested records;
the union itself has no `Key` enum. The option requires at least one reachable
record with retained known fields after field, branch, and opaque selections.
Unreachable source definitions do not satisfy that requirement.

## Validation boundaries

Without a projection, retained SDK fields preserve requiredness and nullability:
required `T`, required nullable `T?`, optional nonnullable `T?`, and optional
nullable `JSONPresence<T>`. Required initializer arguments never have defaults.
Numeric fields use exact `JSONNumber`. Closed enums reject unknown values. Open
scalar unions whose unconstrained scalar branch subsumes every other same-type
literal branch keep that scalar type; this is set inclusion, not a fallback.

`fields` intentionally defines a partial validation boundary: omitted fields
become opaque additional values, including on an originally closed object. Kept
fields retain their SDK requirements. `opaque` removes validation at precisely
the named subtree. A tagged union's omitted `branches` are opaque to that
projection, like future tags. Original node constraints remain in the graph's
`sourceNodes`, and the full source remains in the hashed upstream snapshot.

Known selected tags always decode their selected record and fail if malformed.
Unknown string tags preserve their entire JSON payload. `anyOf` chooses the first
valid source branch and preserves its complete payload; `oneOf` requires exactly
one valid branch on decode and encode. A nullable `oneOf` is simplified only when
it has exactly one explicit null branch and every other branch is proven to
exclude null. Ambiguous forms such as `oneOf: [{}, {"type": "null"}]`, duplicate
null branches, and nullable alternatives fail generation at the source pointer.
Boolean constants use generated single-case literal codecs, including in arrays,
typed additional values and unions. Their public `.value` case encodes only the
declared boolean. Boolean `stream` unions remain associated unions and preserve
absent/false/true/null according to each source branch.
Extra fields cannot override a known key. Closed objects reject extras; typed
extras validate every value.

The reader rejects unknown assertion keywords, invalid combinations, unsupported
dialects, and unresolved references with source identity and JSON Pointer. It
reads every pinned official root plus the local characterization schema in
qualification tests. The emitter deliberately rejects integer specializations,
null-only emitted values, scalar/array top-level declarations, and impossible
direct recursive record layouts until a supported projection or codec is added.
Array indirection and generated indirect unions are compiled fixtures.

`compatibility.json` holds explicit exceptions scoped to a `root` and a separately
named `projection`. Every rule requires a unique `id`, absolute `pointer`,
`operation`, `reason`, `source` provenance, and nonempty `fixtures` paths. Fixtures
must exist inside the repository; their content hashes are generation inputs.
Compatibility applies before field projection, preserves the original source nodes,
and records the rule in generated headers. It never changes the pinned SDK
snapshot. Unknown options, invalid operations, unused projection identities,
and attempts to weaken a tagged discriminator fail. Discriminator protection
accounts for the selected union branches and follows referenced tag definitions.

| Operation | Payload and meaning |
| --- | --- |
| `optional` | A currently required field may be absent; its nullability stays unchanged. |
| `nullable` | A currently nonnullable field may be null; its requiredness stays unchanged. |
| `enumValues` | `values` contains distinct new raw strings appended to a closed source enum. |
| `openEnum` | Represents a source enum as `OpenWireValue<Known>` and retains unknown strings. |
| `additionalField` | `pointer` addresses a new `/properties/name`; `schema` defines its exact shape, with `required` defaulting to false. |

For example, Anthropic provider thinking blocks historically omit `signature`:

```json
{
  "id": "anthropic-incoming-thinking-signature",
  "root": "AnthropicMessage",
  "projection": "AnthropicContentBlock",
  "pointer": "#/definitions/ThinkingBlock/properties/signature",
  "operation": "optional",
  "reason": "Existing provider thinking blocks may omit a signature; present values must be strings.",
  "source": "@anthropic-ai/sdk@0.125.0 resources/messages/messages.ts; existing public sanitizer behavior",
  "fixtures": ["Tests/LittleSwitchWireTests/Anthropic/AnthropicMessageWireTests.swift"]
}
```

Core still owns normalization: an incoming usage projection can preserve missing
and null counters while buffered parsing rejects null and streaming state treats
it as no update. An output-only opaque projection can preserve an existing public
fragment without broadening the corresponding incoming typed decoder. Neither
mechanism authorizes publication or execution of an unknown tool.

## Ownership and evidence

`generated-swift.json` owns exact relative Swift paths and SHA-256 hashes and
records hashes of all generation inputs. Per-file headers identify SDK/version
(or local fixture), source root/pointer, schema hash, projection hash, and
compatibility hash. Only a previous manifest's paths can be removed. Absolute
paths, `..`, symlink ancestors, case-insensitive collisions, and overwriting
unowned files fail before installation. Formatting applies only to generated
temporary output. Schema failures install no partial generation.

The fixtures are generated into a separate `LittleSwitchWireContractFixtures`
module. `GeneratedContractTests` imports it normally, so construction tests verify
public APIs rather than Swift's internal memberwise initializers. This suite
exercises exact numbers, all presence states, closed enums, additional fields,
tagged and untagged unions, boolean request branches, and recursive values.

Generation also owns the `Generated/Qualification` cases and registry in that
fixture module. Every emitted declaration gets compiled samples for its JSON
round trips and validation errors, including record presence states, enum values,
union branches and unknown tags. `GeneratedWireQualificationTests` compares the
complete JSON value or the exact error category and path. The adapter tests remain
the evidence for provider compatibility, privacy and tool authorization; generated
samples qualify the codecs themselves.

Sample construction explores a deterministic set of candidate values, varying
one record field at a time. It is not a complete search of all values a schema
allows. An overlapping union can therefore have a valid branch for which this
search cannot construct an exclusive witness. Generation then reports an
automatic qualification limit at the contract's source pointer and installs no
partial output; it does not declare the source schema invalid. Extend the search
with a focused regression or deliberately narrow the consumed projection after
reviewing its validation boundary. Do not weaken the codec to make a sample pass.

Useful scoped commands:

```sh
mise run tools:test -- --filter 'Contract'
mise run swift:test -- --filter 'GeneratedContractTests|GeneratedWireQualificationTests'
mise run schemas:generate
mise run schemas:check
```
