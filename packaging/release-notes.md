## Improvements

- **Use LittleSwitch models in ChatGPT Chat.** A dedicated ChatGPT connection adds your selected models alongside ChatGPT's own choices. Start text conversations, receive streaming replies, and return to custom-model conversations from the chat history.
- Update announcements use shorter wording in English and French.

## Fixes

- **Codex conversations continue across changes to models and available tools.** Earlier calls to tools that are no longer available remain readable context, without encouraging the model to call those retired tools again. This addresses unexpected exec calls from older conversation history.
- Tool names remain distinct across namespaces and protocol conversions, including names with visually identical Unicode characters. A tool call resolves only to an unambiguous tool declared for the current request.
