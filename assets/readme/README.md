# README visuals

## Menu bar

The two SVGs show the same three menu-bar tabs in horizontal and stacked layouts.
The main README selects the stacked layout on narrow screens.

These are editable vector mockups based on the supplied September 16, 2026
screenshots and the menu-bar views in `Sources/LittleSwitchUI/MenuBar`.
Labels use the app's English copy. Usage figures are illustrative; the overview
totals match the Claude and Codex examples. Model choices are illustrative,
including a local Ollama example.

Keep the shared `<defs>` panel content identical in both files when editing.
Only the canvas size and final panel positions differ. Both SVGs are self-contained:
no remote images, fonts, scripts, or build dependencies.

The Claude, Claude Code, OpenAI/Codex, and OpenCode geometry comes from the
app's existing LobeHub icon assets. See [third-party notices](../../THIRD_PARTY_NOTICES.md)
for provenance and the MIT license.

## Setup video

[`quick-start/video.mp4`](quick-start/video.mp4) is a 48-second
walkthrough: the website's control deck, menu bar, Settings, an Ollama provider,
Claude model routing, and gateway activity. The video is silent H.264 at
1920 × 1200, 24 fps. Usage and request activity are illustrative.

The main README embeds the video using a GitHub-hosted attachment URL on its
own line, which renders GitHub's native video player. Keep the MP4 here as the
source of that upload. When replacing the video, upload the new MP4 to the same
repository's attachments and update the URL in the main README.

`quick-start/poster.png` is an unmodified frame at 1.5 seconds, retained for uses
outside GitHub.

Open [`quick-start/index.html`](quick-start/index.html) in a browser to edit or
preview the animation. It runs locally without a build step or remote assets.
Use Play and the timeline, or `window.demo.seek(seconds)`, to review each scene.
The capture canvas is 1920 × 1200; playback controls sit outside it.

The unmodified brand assets come from `alfred-labs/little-switch-pages`:

- `app-icon.png`: `public/assets/app-icon.png`.
- `control-deck.png`: `public/assets/photoreal/little-switch-assembled-square-v1.png`.

Client icons share the LobeHub provenance noted above. The walkthrough uses
`ollama:glm5.3` as its example model and does not connect to a real provider or
change application settings.
