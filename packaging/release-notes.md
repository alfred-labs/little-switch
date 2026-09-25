## Improvements

- **Choose a dedicated model for ChatGPT Chat.** After updating, select it once in Settings → ChatGPT, independently of Codex's default and exposed models. Chat shows that model alongside its native choices, without using the reasoning slider to switch between LittleSwitch models.
- **Connect Codex and ChatGPT together.** The Codex switch connects or disconnects both with one desktop relaunch. On first use, LittleSwitch asks for a Chat model; the choice is kept when you disconnect.
- ChatGPT settings use two compact sections with shorter explanations. A relaunch notice appears only when applying a pending model change to a connected Chat.

## Fixes

- Pending Chat model changes survive navigation and leave the active model unchanged until Apply. A failed connection or relaunch keeps a recovery path through Reload or Disconnect.
- Queued Chat requests stop if their selected model changes or becomes unavailable, preventing a request from using an outdated model selection.
