# Trace correlation reference

Read only the sections needed for the incident. Paths below are relative to the
repository root unless they start with `~/`.

## Compact index and retention

`errors.jsonl` is written on the first failed request by builds that include the
error index. Each row contains `eventID`, `timestamp` (ISO 8601), optional `status`,
available method/path/provider/model context and `failure`. The failure has `kind`,
`message` and optional `toolName` / `toolNamespace`. Tool fields are bounded to
512 Unicode scalars with an ellipsis when truncated. The file has mode 0600.

The index retains up to 1 MiB independently of traffic-segment rotation, with the
same configured age policy (seven days by default). Full traffic defaults to forty
10 MiB segments, so busy traffic can disappear much earlier than seven days.
Collect relevant evidence promptly. Absence can mean an older build, retention,
no indexed failure or persistence trouble. Check `TrafficLogStore` persistence
state and unified logging category `traffic-store` when needed.

Searching this compact index by UUID is usually sufficient. Avoid printing raw
matching traffic lines: they can contain complete base64-encoded private payloads.

## Raw traffic records

Each JSONL row is a `TrafficRecord` with `eventID`, `sequence`, `timestamp` and
`action`. Swift's synthesized associated-value encoding usually stores the payload
as `action[actionName]["_0"]`. Inspect the selected action before decoding it.
Header collections are arrays of `{ "name": ..., "value": ... }` objects, not
dictionaries. Extract only the selected header names from that array.

| Action | Useful fields |
| --- | --- |
| `started` | method, path, selected task/session headers |
| `routed` | client, requested model identifier, resolved target |
| `claudeRequestBody` | base64 original client body; the legacy name also covers Codex |
| `upstreamRequest` | attempt, provider/model, URL, base64 body actually sent |
| `upstreamResponseHead` | attempt, status, headers |
| `upstreamResponseChunk` | attempt, `bytes` containing base64 wire data |
| `clientResponseChunk` | base64 bytes emitted to the client |
| `failed` | status, finishedAt, failure details |
| `completed` / `cancelled` | terminal lifecycle |

**Raw traffic numeric dates use seconds since 2001-01-01, not Unix time.** Add
978307200 before converting with a Unix-time function. For example:

```python
from datetime import datetime, timezone
incident_utc = datetime.fromtimestamp(record["timestamp"] + 978307200, timezone.utc)
```

Parse selected records locally, sort by sequence and group upstream chunks by
attempt. Base64-decode and concatenate chunks before parsing SSE: a frame, name or
UTF-8 sequence can cross chunk boundaries. Report only the needed event types,
terminal status, tool identities, counts and selected routing metadata.

A gateway `failed` record may retain HTTP status 200 after headers were committed.
Distinguish provider `response.failed`, EOF without a terminal, contract rejection,
client disconnect and cancellation. A later Codex retry commonly has another
gateway UUID; a bridge follow-up within one request increments `attempt`.

## Tool permissions and source entry points

Inspect the tools and selection on that attempt's `upstreamRequest`, not just the
initial client body. `allowed_tools` can exclude a declared tool, including via an
empty automatic selection. A namespace child and a top-level name are distinct;
function/custom kinds also matter. Chat names may arrive as fragments. History
reserves names but does not authorize new calls. Do not repair an invented name by
guessing what the model intended.

Find source with `rg --files` / `rg`; useful entry points are:

- `ProviderToolContractCatalog`, `ProviderToolAllowedSelection`,
  `ProviderToolNamespaceResolver`: declarations, selection and permitted aliases.
- `ProviderToolResponse`, `GatewayProviderToolContract`, `GatewayUpstreamResponseTrace`:
  validation boundary and upstream byte capture.
- `GatewayResponsesWebSearchStreamTurn`, `GatewayResponsesWebSearchStreaming`,
  `GatewayResponsesChatCompletions`, `GatewayTraffic`: native, bridge and adapter failures.
- `OpenAIResponsesStreamFailureWording`, `GatewayCommittedStreamFailure`,
  `TrafficFailure`: public wording and local diagnostic propagation.
- `TrafficErrorLog`, `TrafficErrorRecord`, `TrafficLogStore`: persistence and retention.

When fixing this area, cover native direct Responses, the search bridge and Chat
Completions adaptation when affected. Assert the same UUID in emitted errors and
the terminal log, the observed name, a failed lifecycle and absence of a successful
terminal. Useful suites include `GatewayUndeclaredToolFailureTests`,
`GatewayPortableStreamFailureTests`, `ProviderToolAllowedSelectionTests`,
`TrafficFailureDiagnosticTests` and `TrafficErrorLogTests`.

## Checking goal and Codex retries

If task tools cannot provide the needed evidence, locate the selected task's
rollout under `~/.codex/sessions/`. Codex databases currently include
`~/.codex/goals_1.sqlite` and `~/.codex/logs_2.sqlite`; discover the current files and
inspect their schema before querying. Open SQLite with `mode=ro`, never in a mode
that creates a missing file. Select the task ID, relevant timestamps, goal status
or retry records only; objectives and unrelated task messages are private.

Search the selected rollout for actual `create_goal`, `get_goal`, `update_goal`
calls and lifecycle events. Their presence in tool definitions alone proves no
execution. An absent goal row does not reconstruct all historical state.

## Replay only to resolve an open question

Use authorization already given for the selected provider and scope. Choose one
bounded probe first, with a timeout and explicit output cap. Preserve the original
body in memory; record which fields changed. A cap, removed goal definitions,
different cache reuse, changed model mapping or a new time can change the outcome.
Repeated provider output is not guaranteed, and a timeout is not a successful
tool-free completion.

Keep `.env` values, credentials, payloads and provider headers out of argv, shell
tracing, snapshots and saved probe files. Load secrets only into the probe's memory
and supply credentialed curl configuration through stdin (`curl --config -`), using
the configured authentication scheme. Execute no tool suggested by replay output.

One HTTP client's 403 does not prove a bad API key: inspect a sanitized status and
error classification. A normal curl probe can distinguish an HTTP-client/WAF
rejection from a provider-model error; do not bypass a confirmed access restriction.
Stop when the uncertainty is resolved or the bound is reached. Never keep replaying
a large private context as a substitute for a synthetic regression test.
