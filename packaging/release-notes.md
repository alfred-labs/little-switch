## Breaking changes

- **Apply the Codex configuration again after upgrading.** The updated configuration lets Codex choose its own tool mode instead of forcing direct calls. Applying it restarts Codex Desktop, so finish active work first.

## Improvements

- **LittleSwitch is available in French and English.** Menus, settings, dialogs, status messages and help follow the application language, with locale-aware numbers and usage summaries.
- **Image support reflects observed model capabilities.** Eligible models are checked in the background, and provider details distinguish advertised support from verified, refused, inconclusive and manually forced results. Check details include duration and token usage when available. Fresh results are reused for seven days, and manual overrides are preserved.
- Capability checks send small synthetic requests and can consume provider tokens. New image-check results do not restart clients or rewrite their active catalogs; apply the Codex or OpenCode configuration to publish updated capabilities.

## Fixes

- **Custom tools such as exec work with providers that require function calls.** The gateway uses capability checks to select a compatible format while preserving free-form input, namespaces, conversation history and streaming output. Tool execution remains with the client, and native custom calls remain unchanged when supported.
- **Image conversations survive text-only models and compaction.** The gateway omits unsupported attachments from the outgoing request while retaining received images for a later image-capable model. A precise image rejection triggers one retry without attachments rather than losing the conversation.
- Images returned by tools reach the model as image attachments and remain associated with the correct tool result, including parallel calls.
- An image-compatibility retry reuses completed web searches instead of executing them again.
