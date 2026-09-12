---
name: troubleshooting-little-switch
description: Use when LittleSwitch requests fail, Codex shows Reconnexion en cours, stream disconnected or Internal server error, a provider calls an unauthorized tool, or an incident needs correlation across gateway logs, retries and goal state.
---

# Troubleshooting LittleSwitch

Use the UUID and the recorded wire exchange to locate the failing boundary. Keep
observations separate from hypotheses about the provider, adapters or Codex.

## Find the incident

Start with the reported error ID, task URL and time. The error ID is the gateway
request's `eventID`; it is not the Codex task ID, provider response ID or attempt.
For a Codex task, use the available task-reading tool before inspecting session
files. A UI retry label such as `/5` does not establish five recorded attempts.

| Evidence | Location and interpretation |
| --- | --- |
| Compact failures | `~/Library/Application Support/LittleSwitch/Logs/errors.jsonl`: UUID, ISO 8601 time, route context, failure, tool name and namespace |
| Full exchanges | Same directory, `traffic-*.jsonl`: correlate `eventID`, order by `sequence`, separate upstream `attempt` values |
| Task association | Selected request's `thread-id` / `session-id` headers; inspect only these fields |
| Older failures | May lack the compact index, UUID in public wording or tool metadata; match retained traffic and task timestamps |

Read [trace-correlation.md](references/trace-correlation.md) when decoding raw
traffic, comparing tool permissions, checking goal or preparing a replay. It gives
the timestamp epoch, action schema and source entry points.

## Interpret the evidence

An upstream HTTP 200 opens a stream; inspect its terminal event and the gateway's
terminal action. For `undeclaredTool`, compare the observed identity with the
**actual upstream request for that attempt**, including `allowed_tools`, namespace,
function/custom kind and any declared alias bindings. A declaration or historical
call alone does not grant permission. Preserve the observed name before alias
resolution in the diagnosis.

If goal is suspected, check evidence for the selected task. Tool definitions are
not executions. An empty goal table and absence of recorded calls support only
“no observed link”; they do not establish a causal experiment.

## Reproduce and verify

Prefer a synthetic failing Swift Testing case once the trace identifies the
boundary. Read the replay section of the reference only if a live request would
resolve a remaining question. Use existing authorization and the safety rules in
[AGENTS.md](../../../AGENTS.md), especially preserving the running gateway and
keeping credentials and private payloads out of command arguments and reports.

For runtime changes, run the focused test, then `mise run check`; check its actual
exit status. For real-app validation, follow
[computer-use-validation.md](../../../docs/computer-use-validation.md). The user
relaunches LittleSwitch; verify the running build before drawing conclusions.

Report: UUID, incident time with timezone, provider/model and attempt, observed
failure, supporting evidence, unresolved hypothesis, and exact verification result.
Include relevant log locations, without copying private bodies or tool arguments.

Common mistakes: reading base64 matches as clear text, treating stream HTTP 200
as completion, blaming a declared goal tool, changing tool permissions to suppress
an error, or treating a missing retained trace as proof that nothing happened.
