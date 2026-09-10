# Provider Request Queue

LittleSwitch limits concurrent inferences per provider. Claude Desktop, Claude Code, Codex, and OpenCode share exactly the same capacity when they target that provider, regardless of model or the number of agents the client spawns.

## Behavior

- The limit is configurable from 1 to 32 in the provider editor.
- The default is 2 for z.ai and 4 for other providers. The z.ai policy describes dynamic concurrency without publishing a universal ceiling, so the conservative default remains adjustable.
- When capacity is full, valid requests enter a strict per-provider FIFO for up to five minutes.
- A queue accepts at most 128 requests and 256 MiB of retained bodies. Saturation, budget overrun, timeout, or invalidation answers `503` with `Retry-After: 30` and the client's native error schema.
- A limit change preserves already-running inferences. A decrease may therefore temporarily show more active requests than the new limit. No new permit is granted until the count returns under the ceiling.
- Removing a provider, or changing its endpoint, authentication, or credential, invalidates pending requests. Already-running requests finish with their immutable snapshot.
- Image retries and successive web-search turns belong to the same inference and keep a single permit until the body sent to the client is complete.

Health, catalogue, and public `count_tokens` endpoints bypass the queue. The auxiliary initial-usage count is also separated to avoid a deadlock with the inference whose first event it completes. The 256 MiB budget covers bodies already validated and queued, not bodies still being collected before routing. This limit is detailed in [`known-limitations.md`](known-limitations.md).

## Native client limits

The gateway queue is the exact authority. LittleSwitch also writes native hints to reduce upstream bursts:

- When the Claude Code integration is applied, Claude Code and local sessions in Claude Desktop's Code tab receive a concurrent-sub-agent limit and a parallel-execution limit for read-only tools and sub-agents. The default model's provider determines these values.
- Codex receives `agents.max_concurrent_threads_per_session = max(1, limit - 1)`, because its documentation excludes the main thread from that counter.

These native settings are pressure optimizations, not a security boundary. Only the shared FIFO covers all processes and all clients.

## Monitoring

Settings → Common shows the global state and a line per provider with active capacity, waiting count, and the age of the oldest request. The menu bar exposes the same global snapshot. It shows the gateway state when starting, idle, or unavailable, then the totals during activity, for example `5 running · 10 waiting`. The item opens this section directly.

## References

- [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Claude Code environment variables](https://code.claude.com/docs/en/env-vars)
- [Claude Desktop third-party configuration](https://claude.com/docs/third-party/claude-desktop/configuration)
- [GLM Coding Plan concurrency policy](https://docs.z.ai/devpack/usage-policy)
- [Claude Desktop MDM configuration](https://claude.com/docs/third-party/claude-desktop/mdm), kept for future managed-deployment support
- [Unofficial Claude Code env-vars snapshot](https://gist.github.com/jedisct1/9627644cda1c3929affe9b1ce8eaf714), kept as a research lead and not as a normative source
