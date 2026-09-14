## Improvements

- **Long-running requests have more time to finish.** The gateway's default timeout increases from two minutes to ten minutes across providers, including image generation.

## Fixes

- **Image generation and editing work in Codex through LittleSwitch.** Native image requests preserve the existing ChatGPT sign-in or OpenAI API key instead of failing with an unknown-endpoint error. Codex subscription users can keep generating and editing images without configuring a separate API key.
