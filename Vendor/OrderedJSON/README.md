# OrderedJSON maintained source copy

This package preserves the OrderedJSON product from swift-json-schema 0.14.0,
revision `88abaf2e821f55f7c3c04eb53385b3c0dd2fbf8f`. Its only dependency is
OrderedCollections from swift-collections 1.6.0. The nine upstream Swift files,
three upstream test files, and notices are copied without formatting changes;
only the five source files listed in the patches below differ from upstream.

The parser conformance resources are the 318 `test_parsing` fixtures from
JSONTestSuite revision `1ef36fa01286573e846ac449e8683f8833c5b26a`: 95 accepted,
188 rejected, and 35 implementation-defined cases whose decisions are pinned
by the upstream test. The corpus has its own MIT notice beside the resources.

`provenance.json` inventories every owned file and records upstream and current
SHA-256 hashes. Only files changed by a listed patch have saved originals under
`Upstream`. Each patch is a strict unified diff applied in order; the Node check
reconstructs current source in memory from the original, without modifying files
or consulting a package checkout. Original upstream files and corpus inputs are
not silently refreshed by the check.

## Local patches

- `0001-parser-string-buffer.patch`: construct the completed string from a
  borrowed scalar buffer instead of the generic collection overload. The
  measured release history parse fell from 43.274 ms to 6.296 ms and from about
  1.72 million allocations to 16,864.
- `0002-strict-utf8.patch`: reject overlong three-/four-byte UTF-8 sequences in
  the public parser. The original scalar scan accepted invalid encodings of
  ASCII characters, including NUL and object keys. Local raw-byte regressions
  reproduced the defect before this correction; the Wire ingress guard remains.
- `0003-quoted-segments.patch`: append unescaped UTF-8 spans together while
  preserving the original escape mapping. Release serialization measurements
  over five repetitions fell from 11.55 to 0.479 ms for history, 2.76 to 0.84 ms
  for tools, and 2.27 to 0.81 microseconds for a small event. Long multiline
  Unicode improved from 6.39 to 1.28 ms with a documented tradeoff of roughly
  6,000 additional segment allocations and 22% more requested bytes.
- `0004-exact-unicode-keys.patch`: replace the `JSONValue.object` associated
  value with `JSONObject`, an ordered collection whose member names compare by
  decoded UTF-8 bytes instead of Swift's canonical String equivalence. Equality
  and hashing remain order-independent. This intentionally changes the public
  object storage API; string subscripting and dictionary literals remain usable.
- `0005-exact-object-parser.patch`: build exact-key objects when parsing, keeping
  distinct Unicode spellings and the existing last-occurrence duplicate policy.
- `0006-exact-object-codable.patch` and `0007-exact-object-literals.patch`: adapt
  the existing construction paths to exact-key storage.

The exact-key change was compared against the preceding maintained version with
the same synthetic 200-message history, 200-tool schema list and small streaming
event. Five alternating Swift 6.4 `-O` runs (identical coverage instrumentation
on both builds) had median parse times of 4.30 → 4.64 ms, 1.01 → 1.06 ms and
2.55 → 2.64 µs respectively. Serialization was 1.40 → 1.35 ms, 0.196 → 0.202 ms
and 0.517 → 0.515 µs; complete output sizes and checksums matched. The modest
parsing cost buys exact object identity; these are not upstream benchmark claims.

These are recorded task measurements, not benchmarks performed by the provenance
check. The patches preserve numeric handling, object order and the duplicate-key
policy. Source changes beyond them require a separate reviewed diff.

Use `parse` and `serialized` for lossless JSON interchange, as LittleSwitchWire
does. Generic `Codable` is an interoperability API, not an exact-key codec:
Foundation's keyed encoders/decoders can merge canonically equivalent names
before or after OrderedJSON sees them. Converting an object to a Swift
`Dictionary<String, ...>` has the same limitation. LittleSwitch keeps unknown
fields in `JSONObject` and exposes only ASCII protocol fields to legacy adapters.

## Maintenance

Run `mise run ordered-json:check`, `mise run ordered-json:tools:test` and
`mise run ordered-json:test`. These tasks use the pinned Node 24 and Xcode
environments and are included in `mise run check`. The package tests run
explicitly; testing the root package alone does not execute dependency tests.

On an authorized update, review the new upstream and corpus revisions, preserve
their notices, review/reapply or remove each local patch, and update the inventory
and hashes as an explicit diff. Verify all retained tests and the same complete
wire outputs, UTF-8/exact-number regressions, and release performance fixtures.
Never edit a resolved checkout or regenerate the inventory merely to accept
unexpected files. Keep build artifacts outside this owned directory.
