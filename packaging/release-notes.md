## Improvements

- **Open Claude Desktop, Codex and OpenCode directly from their icons in the menu.** Available icons highlight on hover. Missing applications have disabled icons and switches, and Claude Desktop is disabled when an organization-managed login prevents profile integration.
- **Claude's 1M context follows the capacity reported by the provider.** Detected capacity is authoritative, and the manual 1M switch appears only when the provider does not report a context length.
- **Claude Desktop shows when its model list needs to be applied.** Changes to model names, available families or context capabilities wait for an explicit Apply, which restarts Claude Desktop only if it is running. Refreshing a provider or changing a label does not restart the app automatically.

## Fixes

- Existing Claude Desktop profiles remain recognized when their model list is outdated, so updating LittleSwitch or changing model capabilities does not incorrectly disconnect them or prevent restoration.
- Models with similar names no longer collide in Codex and OpenCode. Existing Codex configurations remain recognized and offer Apply when their catalog needs updating.
- Model selections and unsaved web-search settings remain consistent during background refreshes and failed updates. Failed menu selections return to the applied choice.
- The gateway preserves distinct Unicode field names and provider-specific tool content across protocol conversions. Custom-tool streams also handle providers that omit repeated output from their final response.
- Image-compatibility retries leave tool arguments and unrelated data untouched instead of treating every image-shaped object as an attachment.
- OpenCode settings remain recoverable after interrupted or failed updates, while unrelated settings are preserved. Sensitive settings files retain restrictive permissions during replacement.
- Credential scripts stop on cancellation or timeout, and excessive output produces an error instead of leaving the request waiting indefinitely.
- Escape cancels confirmation dialogs in French as well as English. Settings accessibility labels no longer retain an outdated pending status.
