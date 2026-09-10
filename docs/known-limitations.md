# Known Limitations

## The public token-count endpoint is approximate

LittleSwitch implements Claude Desktop's `POST /v1/messages/count_tokens`
endpoint locally using an intentionally simple deterministic estimate: the
semantic UTF-8 input length divided by four, with a minimum of one token for a
non-empty prompt.

This value is an estimate, not the provider's authoritative tokenizer result
and not the usage used for billing. It can differ from the input-token usage
reported by the selected model after inference, especially for structured tool
content, non-ASCII text, images, and model-specific chat templates.

The local implementation keeps provider behavior uniform. Ollama's
main API on port `11434` does not expose this Anthropic token-counting endpoint.
LittleSwitch therefore does not forward Claude's public `count_tokens` request:
every provider receives the same local estimate and the endpoint remains
available independently of backend capabilities.

## Streaming initial token counts are conditional estimates

Anthropic's [streaming format][anthropic-streaming] normally reports input
usage in `message_start`. Some compatible providers instead start at zero and
publish the authoritative input, cache, and output usage only in the terminal
`message_delta`. This made Claude Code's live workflow and subagent token
counters remain blank with those providers even though terminal usage existed.
Some native providers report a positive start, demonstrating that this is not a
blanket Claude Code custom-provider defect. Live acceptance currently targets
Claude Code 2.1.251.

For successful streaming Anthropic Messages responses, LittleSwitch treats the
two cases separately:

- A positive first direct `message_start` is forwarded byte for byte. The
  already reconstructed public web-search stream preserves that native count.
  Neither path makes an auxiliary count request or shows an estimate row.
- A zero first start triggers the provider's
  `POST /v1/messages/count_tokens` endpoint with a strict projection of the
  exact inference request. The call has a one-second deadline and no retry.
- If that endpoint times out, fails transport, returns a non-success status or
  invalid result, or its circuit is open, LittleSwitch uses the exact same
  semantic UTF-8 divided-by-four estimator as the local public endpoint.
  A nominally successful response with `input_tokens` equal to zero is invalid
  too. This behavior was observed on z.ai / `glm-5.3-flash`, and exercises the
  same fallback rather than showing a blank live counter.
- Only the numeric source bytes of nested initial `usage.input_tokens` are
  replaced. SSE line endings, comments, IDs, key order, unknown start members,
  and every later byte remain provider-authored. LittleSwitch never adds the
  initial estimate to terminal usage or cache fields.

This adapter does not buffer the complete response. Classification is limited
to a 64 KiB prefix and it does not request the next provider chunk while
counting is pending. If the transport already delivered bytes after the start
in that same chunk, only that existing suffix waits behind the start. No later
chunk is read ahead. After the first decision, all later chunks keep their
existing streaming backpressure and are forwarded without reconstruction.
Malformed, oversized, incomplete, or unexpected prefixes fail open to exact
passthrough. Because the rewritten body length can differ, stale upstream body
length and digest validators are removed on this adapted path. A zero-start
provider can therefore add at most one second before the first content becomes
visible, but does not turn the response into a buffered one.

This fail-open behavior belongs only to the usage estimator. The provider tool
contract is validated first: malformed tool output, undeclared calls, and hosted
provider tools produce a controlled protocol error rather than bypassing the
ownership boundary. See the internal portable tool contract.

Provider counting remains an estimate for this early display even when the
endpoint succeeds. Chat templates, non-ASCII content, tokenizer revisions, and
provider-side transformations can make it differ from terminal usage. The local
fallback counts image blocks as zero. Neither early value is used for billing,
quota, context admission, cache accounting, or retries.

Healthy count requests have no fixed concurrency limit: a provider can receive
one auxiliary request for each simultaneous zero-start stream. Failure load is
bounded by an in-memory circuit breaker isolated per provider. HTTP 429 opens it
immediately. Three consecutive other count failures also open it for 30 seconds.
After that interval exactly one half-open probe is admitted, while concurrent
inference streams fall back locally without waiting. Admissions carry a circuit
generation, so older in-flight completions cannot close or extend a newer open
or half-open state. A successful current count closes the circuit. Restarting
LittleSwitch clears this transient state.

[anthropic-streaming]: https://platform.claude.com/docs/en/build-with-claude/streaming

## Claude exposes 200K or 1M, not arbitrary context modes

LittleSwitch records the exact context window reported through
`max_input_tokens`, `max_model_len`, `context_length`, or `context_window`.
Ollama models that omit it from `/v1/models` are inspected through `/api/show`.
Because providers may omit or misreport this metadata, each discovered model
also accepts a user override. No capacity is inferred from a model name.

Claude Desktop does not expose an arbitrary per-model compact window through
the custom-provider catalog. A model with an effective context below one
million tokens therefore remains in Claude's standard 200K mode even when its
recorded capacity is, for example, 262,144 or 400,000. At one million tokens or
more, LittleSwitch advertises the optional `[1m]` variant. The gateway accepts
that exact suffix only for eligible models and removes it before forwarding the
provider model ID.

## Traffic logs retain complete local payloads

The internal diagnostic store retains the complete Claude request body, rewritten
upstream request body, provider response, and raw SSE bytes. Prompt bodies can
therefore contain user content or secrets entered inside a prompt. Model
Switch does not heuristically redact arbitrary body strings because doing so
would make the diagnostic record incomplete.

Known credential headers are masked case-insensitively before capture, including
authorization, API-key, cookie, and provider credential headers. Sensitive URL
query values are masked as well. Apple unified logging receives metadata-only
summaries and never receives headers or bodies.

Full records remain local in
`~/Library/Application Support/LittleSwitch/Logs`. The store uses user-only
`0600` segment files, rotates before 10 MiB when possible, keeps at most forty
segments, and removes segments older than seven days. An unusually large event
can lose its oldest portion during rotation. The retained event records that it
is partial. There is no Logs page or Clear control in Settings.

If the directory cannot be created or written, proxy traffic continues and the
in-memory store remains available. Operational logging reports persistence
failures. The store retries persistence on later traffic.

Streaming payloads are coalesced into 64 KiB traffic updates before they reach
the log store. The store's internal live-update queue is nevertheless
unbounded. A stalled log
consumer combined with an unusually large or long-lived stream can therefore
cause transient process-memory growth and increasing copy cost even though disk
segments rotate. The gateway still forwards network chunks immediately. This
limitation affects diagnostics, not client backpressure.

## Web search is locally orchestrated

Web search currently has four adapters, Firecrawl, Tavily, Brave, and Exa, and only
one search provider can be active. Each adapter dials its provider's official
hosted API with a fixed endpoint (`https://api.firecrawl.dev/v2`,
`https://api.tavily.com`, `https://api.search.brave.com`, and `https://api.exa.ai`). Stored
configurations carry no URL of their own. Tavily and Brave clamp each search to
20 results.

A Claude request's `user_location` (the geographic filter behind
locale-aware searches) is forwarded by the Firecrawl adapter but has no Tavily
or Brave equivalent: with Tavily or Brave active, the location is accepted on
the wire and then dropped, so those searches run unfiltered rather than
geo-restricted. Brave also has no server-side domain filters: the
`allowed_domains`/`blocked_domains` filters are dropped the same way, while the
country filter maps to Brave's native `country` parameter.

Exa uses `auto` search with 1–100 results and forwards domain filters natively.
The country maps to `userLocation`. City and region hints are omitted because
Exa only accepts an ISO country code. Exa requests highlights capped at 4,000
characters per result with full text disabled, then applies the same aggregate
content budget as the other adapters. See the [Exa API reference](https://exa.ai/docs/reference/search).

When search is **Disabled**, LittleSwitch removes supported native search
declarations from Anthropic and Responses requests and gives them a zero search
budget. An explicit Responses `external_web_access: false` has the same effect.
A forced choice naming the removed search tool becomes `auto` when other tools
remain. With no tools left, the choice is removed. The gateway does not read a
search key or delegate the disabled operation to the model provider. Completed
history and namespace tools still receive their normal adaptation. Ordinary
client tools, including a client tool named `web_search`, retain their ownership.

For the native-tool bridge, the client must declare a supported search tool and
the routed model must call the private function generated for that request.
LittleSwitch chooses a private name that does not collide with client tools or
their history. Models that do not use tools reliably may therefore ignore web
search even when it is enabled.

OpenCode uses the managed `mcp.web` connection to the stateless
Streamable HTTP endpoint `POST /api/mcp`, which advertises `search(query)`.
OpenCode combines the server and tool names, exposing exactly `web_search`.
The endpoint still accepts the former `web_search` name for clients that cached
the old catalog, without advertising a duplicate tool.
It runs the applied LittleSwitch search provider and returns titles, URLs and
snippets. No Exa/Parallel environment flag or provider key is written to OpenCode.
Search-provider changes apply to the next tool call. The connection stays present
when search is disabled, and calls then return an MCP tool error with guidance.
Each call honors **Results per search**, but **Maximum searches** cannot limit an
OpenCode conversation because the endpoint has no conversation identity. It does
not provide SSE subscriptions, resumable sessions, prompts or resources.

Profiles connected before MCP was introduced need **Apply** once, followed by a
new OpenCode process. The profile journal preserves the MCP entry that existed
when this new path became managed, including entries added after the original
connection. Restore keeps later external changes and other MCP servers intact.
Project configuration and explicit OpenCode permissions can still override the
managed connection or deny its tool. MCP calls are traced separately from model
requests and do not contribute token usage or model request counts.

OpenCode custom providers default to text-only input if their model entries omit
`modalities`. The managed profile exports `modalities.input` and `.output` using
the same image-input policy as the gateway and Codex: a provider override wins,
then detected capability, and unknown capability permits images. This avoids
OpenCode replacing the image with an unsupported-input message before the model
request. It does not establish that an unknown upstream model supports vision. The upstream remains responsible for accepting the input. Older journal model
entries retain their absent modalities when decoded for restoration.

The Anthropic bridge accepts `web_search_20250305`, `web_search_20260209`, and
`web_search_20260318`. The Responses bridge accepts `web_search`,
`web_search_preview`, and `web_search_preview_2025_03_11`. Unknown variants fail
explicitly instead of being passed through to the provider. Anthropic search is
always a direct call.
`web_search_20260209` and later default `allowed_callers` to
`["code_execution_20260120"]`, Anthropic's dynamic filtering, which runs the
search from inside server-side code execution so that only the relevant part
of each result reaches the context window. LittleSwitch owns no code-execution
tool to host that loop, so it answers those requests with a direct search and
labels the projected blocks `"caller": {"type": "direct"}`, the same shape the
first-party API returns when dynamic filtering does not run. The client
receives the adapter's snippets unfiltered, and `response_inclusion` has
nothing to exclude. Refusing the newer versions instead, which is what this
bridge did until a Claude upgrade started sending them, answered HTTP 400 to
every turn that merely declared the tool: the conversation failed, and not just
the search.

Claude Desktop, unlike the CLI, never declares the built-in tool on a managed
gateway (its client disables WebSearch for gateway providers), so the bridge
above serves CLI sessions only. Desktop search arrives through the profile's
`managedMcpServers` entry pointing the built-in `websearch` server at
`POST /api/web-search` (`provider: "custom"`. Profiles written before the
gateway's own namespace moved to `/api/*` still hold
`/_little_switch/web_search`, which keeps answering during the compat
window): one POST with `{"q": …}`
maps to one provider search and returns the flat `{"results": […]}` array
Desktop's own schema documents. That path carries no filters, honors
`resultsLimit`, and, being one POST per search with no conversation identity,
ignores **Maximum searches**. A disabled search configuration answers HTTP 503.
The bundled MCP server and custom HTTPS configuration are documented by Claude. The `{q}`/`results` mapping was also checked in the installed Desktop archive.
A Desktop upgrade still requires a wire-contract check because a changed result
shape can surface as empty searches. The evidence and ownership boundary are in
the internal portable tool contract.

The entry's https requirement is why the gateway listener speaks two wire
protocols on one port: Desktop validates the built-in server's `customUrl` as
https-only, plain http on the loopback is rejected, while Codex
speaks plain http. The first inbound byte decides
(`0x16` is a TLS ClientHello), so both transports coexist. There is no
network-exposure setting anymore: a LAN hostname cannot be vouched for by the
loopback identity, so the gateway binds 127.0.0.1 unconditionally and old
configurations carrying `gatewayAccessMode` decode the key away silently.
Desktop's engine primes `ca-bundle.pem` from
the keychain at launch. Terminal Claude Code's runtime consults the
macOS user trust domain natively, it selects its certificate sources with
`CLAUDE_CODE_CERT_STORE` (default `bundled,system`), and the `system` source
reads user-domain trust settings (measured 2026-09-06: the same anchor
Desktop accepts is honored, with no `NODE_EXTRA_CA_CERTS` anywhere). The
managed Claude Code settings follow the Desktop profile's rule: an `https://`
origin while the anchor is trusted, `http://` otherwise, the CLI has no
in-app fallback, so an untrusted https origin would kill every session it
starts. The managed Codex profile continues to use plain http.

The managed OpenCode profile uses https for both `/v1` and `/api/mcp`. The local
CA must be trusted in the macOS Keychain. OpenCode 1.18.25's compiled
Bun runtime includes `--use-system-ca`, which loads system trust anchors
([Bun runtime options](https://bun.com/docs/runtime)). Measured 2026-09-09 with
the installed OpenCode binary's embedded runtime: `GET https://127.0.0.1:11436/health`
returns 204 with system CAs, while forcing bundled CAs fails with
`SELF_SIGNED_CERT_IN_CHAIN`. No extra CA file or TLS-verification override was
used. Existing http profiles migrate through Apply, and the changed endpoints
take effect in new OpenCode terminal sessions.

The 2026-09-05 measurement that found terminal Claude Code failing against the
anchor was an attribution error, that run happened while the toggle-revocation bug (fixed the same
evening) had just removed the anchor, and the failure text is identical for
a missing anchor and an ignoring TLS stack. The differential
probe settles trust questions: forcing `CLAUDE_CODE_CERT_STORE=bundled` must
reproduce the failure (bundled roots only, the anchor excluded by
construction). If the default succeeds where the forced-bundled run fails,
the user trust store is being read. For Codex the 2026-09-05 result stands:
its default TLS path ignores the macOS user trust domain, re-verified
2026-09-06 with the anchor present and honored by Desktop, Claude Code, and
`openssl s_client` alike, TCP connects, the handshake is dropped within
milliseconds, and `codex exec` loops on `Reconnecting… waiting for network`.
Codex does ship an escape hatch, but it lives only in the process
environment: `CODEX_CA_CERTIFICATE` (or the generic `SSL_CERT_FILE`) names a
PEM bundle, forces the rustls backend, and layers the bundle over the
platform roots (`codex-rs/http-client/src/custom_ca.rs`). An empty value
counts as unset, no `config.toml` key exists, and an unreadable or
unparsable bundle is a hard client-construction error with no fallback.
With the anchor exported to a file, a full `codex exec` turn completes over
https against the gateway (measured 2026-09-06). Wiring that up would couple
the user's shell to the anchor lifecycle, a stale `CODEX_CA_CERTIFICATE`
path kills every Codex session at construction, http included, which is why
the managed profile stays on http. The listener serves a
`127.0.0.1`/`localhost` leaf under a private authority, both issued in memory
with swift-certificates. A self-signed leaf does not work: Node, what
Desktop's client is built on, answers `DEPTH_ZERO_SELF_SIGNED_CERT` when the
server certificate signs itself, and installing that leaf as an anchor does
not change it. The anchor is therefore the authority, trusted once in the user
domain through Security.framework's native consent prompt at connect and
scoped to the SSL policy, so it vouches for nothing but TLS. What keeps it
from being a standing forgery capability is that the authority's private key
is never stored: it is created in memory, signs this one leaf, and is gone
before issuance returns. Only the leaf's key reaches the Keychain. In Keychain
Access the anchor appears as `LittleSwitch loopback authority`, the
certificate carries that identity in its own subject, since the keychain
derives a certificate item's label from the certificate and discards the one
the caller passes. The anchor survives the Claude toggle: the authority's signing key is
destroyed at issuance, so a lingering anchor cannot vouch for anything that
does not already exist, and revoking it per toggle would only force the
consent prompt back on every reconnect. The full-removal API exists, live
anchor plus every superseded one, but no surface calls it yet. An explicit
"remove trust footprint" action, not the quit or the toggle, is its intended
home. The pair
reissues inside its 30-day renewal margin (825-day validity). A renewal purges
the old anchor, prompts once more, and needs a Desktop restart, since
Desktop's `ca-bundle.pem` trust snapshot is taken at launch. A trust
installation the system refuses keeps the profile on plain http and writes the
Security.framework status to the unified log under the `gateway-tls` category,
so a refusal is distinguishable from a dismissed prompt. A future Desktop
update could also change what its implementation of fetch honors, the failure
mode stays "search stops working," not data
exposure.

Anthropic documents the downgrade as being inside the contract rather than a
liberty this bridge takes: `allowed_callers` "controls how the tool is
presented to Claude and is validated against `tool_choice`, but it is not a
hard API-level block on direct invocation", and a client "should still be
prepared to handle a direct `tool_use` for any tool it defines"
([programmatic tool calling][pctc]). `"caller": {"type": "direct"}` is that
page's own shape for a direct call, and it is what both projections emit, on
the buffered response and in the streamed `content_block_start`.

The versions the bridge now accepts went generally available on 2026-02-17
(`web_search_20260209`, dynamic filtering) and 2026-06-11
(`web_search_20260318`, `response_inclusion`), so any client updated after
those dates can send one.

[pctc]: https://platform.claude.com/docs/en/agents-and-tools/tool-use/programmatic-tool-calling#the-caller-field-in-responses

Eligible streaming requests keep one client SSE connection open across the
local model/search/model loop. Model tokens and the native Claude or Codex
search lifecycle are written incrementally. Each search itself remains one
bounded JSON pause between model turns. A provider that accepts `stream: true`
but returns complete JSON still uses a compatibility fallback at that turn and
therefore cannot provide progressive tokens for that leg.

The current adapters use the snippets returned by Firecrawl Search, Tavily
Search, Brave Search, and the highlights returned by Exa Search. They do not
request or inject scraped page Markdown or provider-generated answers.
Tavily's 429/432/433 quota statuses fold into the shared rate-limited category.
Search queries, snippets, and the model turns that consume them can appear in
the complete local traffic logs described above.

Anthropic's public result shape requires an `encrypted_content` string.
LittleSwitch fills it with a versioned `little-switch-search:v1:` replay token
containing the normalized title, URL, and result text. This is bounded,
self-contained encoded data, not Anthropic ciphertext. It needs no persistent
replay store. Before the next provider request, the gateway converts each owned
call/result pair into readable historical text, preserving call input, sources,
result content, errors, and order. This works after switching model provider,
removing the search declaration, or disabling search. JSON and SSE publish the
same token values. Replay is limited to 100 results and 256 KiB of aggregate
result text, with additional per-field and decoded-payload limits.

Older `little-switch-opaque:` placeholders retain their available source metadata
and explicitly state that result content is unavailable. Foreign provider opaque
tokens cannot be decoded, and malformed, mismatched, or unsupported replay
tokens fail explicitly. LittleSwitch does not send its synthetic replay token
back to a model provider as if that provider had issued it.

OpenAI Responses publishes the query and available source URLs in
`web_search_call` using `action.sources: [{"type": "url", "url": "…"}]`. A failed search has
`status: "failed"` and emits no successful search-completed SSE event. These
values survive the next turn as readable historical context. The public search
item carries no proprietary snippet fields: the model receives result text in
the internal follow-up and can use it in its answer. The gateway cannot recover
source text that an older Responses history never contained.

Validation scope on 2026-09-07: the web-search probes used the live model
provider with a simulated search service. They exercise the gateway's
model/search/model contract. They are not evidence of a real Firecrawl search or
of the Desktop MCP/HTTPS path running end to end.

Each upstream operation uses the transport's 60-second timeout and disconnect
cancellation propagates to the active model or search request. There is no
single orchestration-wide deadline across repeated searches, so a request that
uses the configured maximum repeatedly can remain open for several per-leg
timeouts. The maximum search count, response-size limits, retained-result
budget, and generated-follow-up request limit prevent unbounded memory growth,
but they do not provide a total wall-clock latency guarantee.

## Monitoring access is restricted to loopback

The gateway's only access control is the loopback authority check
(`GatewaySecurity.isAllowedAuthority`, applied by `GatewayAuthorityPolicy`):
a loopback Host on the expected port, and no `Origin` header. No route
validates a key, `ProductIdentity.gatewayAPIKey` is filler written into
client configurations, and nothing compares a presented credential against
it. Anything that reaches the port can therefore read every endpoint. The
loopback-only bind described above is the entire security model, and it is
why no key validation exists.

`/metrics` and `/logs` use this same policy and listener, including the HTTP/TLS
sniffer. Monitoring does not introduce a remote bind, another port or incoming
Bearer authentication. Outgoing OTLP credentials authenticate only the configured
receiver. Docker containers must not use `host.docker.internal` to bypass the
gateway's authority policy. The lab uses OTLP push to published loopback ports.

## Monitoring delivery is bounded and held in memory

Metrics are cumulative for one app process. Restarting the app resets counters and
changes `service.instance.id`. Logs are metadata events, separate from the complete
local traffic captures.

Export queues are held in memory, with no disk spool. Pending logs expire after five
minutes and are limited to 5,000 entries / 5 MiB. Pressure discards the oldest pending
entries. A network failure can leave acceptance uncertain, so a retry can duplicate
a log. Event IDs remain stable to support downstream deduplication. A partial
success is never replayed. Shutdown allows two seconds for a final flush, then
cancels and closes the transports. See [Monitoring](monitoring.md) for the full
catalogue and bounds.

## The provider queue does not cap pre-routing intake

The limit of 128 waiting requests and 256 MiB of retained bodies applies only
after LittleSwitch has collected, validated, and routed a request to a provider.
It does not cap connections or request bodies that are still being collected
before routing. The existing per-request body limit still applies at that stage,
so the queue budget is not a total process-memory guarantee.

The five-minute wait is an interoperability target. A client may close its
connection sooner. Cancellation then removes the waiter and returns its retained
body budget.

FIFO ordering is strict by arrival time within one provider, but it does not
reserve equal shares for applications. A burst from one client can delay another
client that uses the same provider. The gateway cannot distinguish Claude
Desktop from Claude Code on `/v1/messages`, or Codex from OpenCode on
`/v1/responses`.

The native Claude Code and Codex concurrency settings are session-level hints
derived from the provider of each client's default model. They do not replace the
shared provider pool. Claude Code versions older than 2.1.217 can ignore the
subagent limit. Running local sessions can pick up new or changed settings, but
removing or restoring a value requires a new session. Remote, SSH, and cloud
sessions do not necessarily use the Mac's local settings or gateway.

Queue activity and counters are in memory. Restarting the gateway resets them.

## Namespaced Codex tools are adapted independently of search

Codex groups its collaboration and MCP tools into Responses API specs shaped
`{"type": "namespace", "name": "multi_agent_v1", "tools": [...]}` and expects
the matching `namespace` field back alongside `name` on the call. That shape is
specific to the Responses API. Providers that implement plain function calling
ignore the wrapper entirely, so every tool inside it is invisible to the model:
a controlled A/B through the gateway produced zero calls for a tool declared
inside a namespace and three for the same tool declared flat.

The native Responses and Chat Completions adapters flatten those specs into
ordinary function tools with collision-safe names, replay history under the
same binding, and restore the `name` and `namespace` pair on the way back,
which is what Codex resolves against. Flattening without that restoration is
worse than dropping the tools, because the model then calls a name Codex cannot
resolve. Upstream tracks the
same failure for other proxies in [openai/codex#20652][codex-20652] and
[ollama/ollama#15921][ollama-15921].

Namespace declarations, forced choices, and owned history trigger adaptation
even when search is globally disabled, absent from the request, or refused with
`external_web_access: false`. `OpenAIResponsesNativeNamespacing` restores the
public `name`/`namespace` pair for both buffered and streamed calls.
`agent_message` mail (whose `encrypted_content` part holds the plaintext brief on
custom providers) converts to a user message. These conversions require no
search key and do not enable external search. Declared client discovery tools
and their returned references remain client-owned under the
the internal portable tool contract.

These adapters need the complete conversation in `input`. A non-null
`previous_response_id` or `conversation` reference is rejected with HTTP 400
on Chat Completions and on native requests needing namespace, discovery,
web-search, or owned-history adaptation. LittleSwitch does not reconstruct
provider-stored conversations. Null values remain accepted, and transparent
native Responses requests preserve the references for the provider.

The full chat-adapter fix history is in
the internal multi-agent documentation.

Native subagents may also fail for reasons this flattening cannot address:
[openai/codex#24069][codex-24069] reports spawning breaking against a local
provider even when the tools are visible.

[codex-20652]: https://github.com/openai/codex/issues/20652
[ollama-15921]: https://github.com/ollama/ollama/issues/15921
[codex-24069]: https://github.com/openai/codex/issues/24069

## Image turns need reshaping before a native provider accepts them

Some native providers size their completion reserve from an input-token estimate that does
not count image tokens, then validates the total against the context window
with those tokens counted. The sum therefore overflows by exactly the image's
token cost. The arithmetic is visible on the buffered wire and is strikingly
stable, the reported total is 402373 against a 400000-token window whether
the conversation holds 5 items or 448:

| Input tokens | Reported completion | Total |
|---|---|---|
| 2400 | 399973 | 402373 |
| 43300 | 359073 | 402373 |
| 200519 | 201854 | 402373 |

The reserve is `402373 - input`, so the request fails by the same 2373 tokens
every time, the cost of the screenshot. The streamed wire reports none of
this: it answers 200, then fails the response with `"error": null`.

Two conditions drive it and both must be answered.

`reasoning.effort` makes the provider ignore `max_output_tokens` entirely and
take the reserve path. Any value does it, `low`, `medium`, `high` and `max`
all fail identically, and `reasoning` carrying only `summary` is fine, so it
is the presence of the field that matters, not its level. Removing it is not
sufficient on its own: with no budget named, the reserve path still applies.

Naming `max_output_tokens` is not sufficient either, because effort makes the
provider ignore it.

Dropping `reasoning.effort` *and* supplying a budget makes the same requests
succeed, with the image read correctly, on both a 5-item and a 448-item turn.
`ResponsesImageTurnCompatibility` therefore does both on native Responses
requests that carry an image, on the bridged and the transparent path alike.
It leaves text turns untouched, so their bodies stay byte-identical, and it
keeps a budget the client declared itself.

The cost is that image turns lose their explicit reasoning effort and fall
back to the provider's default. That is a deliberate trade against a hard
failure and five re-uploads of a megabyte. The budget is a fixed constant
rather than a value derived from the model's context window, which the request
path does not currently know. It sits far above any Codex turn and far below
the 262k-400k windows these providers advertise, but a provider with a
genuinely small window would need the derivation instead.

## A provider may fail a response without saying why

The Responses contract expects a failed terminal to carry an error object with
a code and a message. Some providers stream `"error": null` instead. The gateway
used to reject that frame as unparseable, which turned a provider-side failure
into `invalidProviderStream("invalidResponse")` and showed Codex a generic
"stream disconnected before completion: Internal server error", a message that
named neither the provider nor the cause, and cost hours of log archaeology.

`validResponsesFailedResponse` now accepts a null or absent error object, since
the terminal itself is well formed. A *present* but malformed error object is
still a rejection. When the payload is missing, the client-facing terminal says
so explicitly rather than claiming an internal error.

Provider text is still never echoed to the client. `fail(message:)` discards
its argument by design, that argument is a diagnostic for the caller's logs,
and the client-visible wording stays a closed set of strings this gateway
authors. Relaying the provider's own message verbatim would leak response
bodies through the failure path.
