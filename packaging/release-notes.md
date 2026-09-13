## Breaking changes

- **Apply the Codex configuration again after upgrading.** Applying or restoring the configuration restarts Codex Desktop, so finish active work before doing so.
- Requests with thinking disabled now use low reasoning effort by default. Choose **Pass through** under **When thinking is off** in the provider's compatibility settings to preserve the client's original parameters.

## Improvements

- **Native and custom models coexist in Codex.** The model picker combines both catalogs in a consistent order. Native OpenAI models keep Codex's own permission reviewer, while custom models use the reviewer selected in LittleSwitch.
- A new OpenAI provider preset simplifies setup and filters non-conversational model families from its catalog.
- **Long Codex conversations can compact through custom providers.** If the conversation exceeds the provider's context limit during compaction, the gateway retries after removing older assistant messages and completed tool exchanges while preserving user messages. Summaries no longer have a fixed local length cap.
- The provider editor offers more room, groups compatibility options and presents model context capacities in a compact table. Connection diagnostics stay folded until opened, and both menus open the same larger About window.
- Saving a provider no longer makes an extra model call to test tool naming.

## Fixes

- Tool identities, results and readable collaboration messages survive API-format conversion and continued conversations. Completed streamed output is retained when the final event omits it.
- Native Codex compaction preserves upstream state. When switching to a custom provider, unreadable native checkpoints are skipped with an explicit notice instead of triggering repeated recovery requests and reconnects.
- Client headers, including the Codex client version, reach upstream providers while credential replacement remains enforced.
- Large and precise numeric values remain intact when requests are rewritten or retried after an image rejection.
- Tool failures include an error ID that can be matched to gateway diagnostics, and interrupted streams report a more specific failure reason.
