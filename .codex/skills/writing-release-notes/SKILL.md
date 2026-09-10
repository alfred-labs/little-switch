---
name: writing-release-notes
description: Use when preparing a Little Switch release — before the chore(release) commit or running the release/publish mise tasks — when asked to write, refresh, or review release notes, a changelog, or "what's in this release" from the diff, or when touching packaging/release-notes.md, the Sparkle appcast description, or the GitHub release body.
---

# Writing Release Notes

## Overview

Release notes describe what changed **for the person using Little Switch**, in behavior terms — never what was done to the code. One file feeds everything: `packaging/release-notes.md` is passed verbatim to the GitHub release body and converted to the Sparkle appcast description by `mise run tools:run -- release appcast`.

## When to Use

- Preparing a release, before the `chore(release)` commit (the notes ship inside it).
- Asked for release notes, a changelog, or the appcast/GitHub release description.
- Editing `packaging/release-notes.md` for any reason.

## Source Range

No git tags exist. The range is everything since the last release commit:

```bash
git log -1 --format=%H --grep='chore(release)'   # <hash>
git log --oneline <hash>..HEAD
```

Candidate commits: every type except `chore` and `test`. Then keep only user-visible behavior — `feat` and `fix` always count; `docs` counts when it documents product behavior; `refactor` counts only when something observable changed (reliability, performance, failure modes). Internal-only work is dropped.

When a commit's user impact is unclear from its message, read the diff (`git show`) — the notes come from the code's behavior, not the message.

## Rewrite the File Entirely

The final file contains **only the upcoming release**. Sections belonging to already-published releases are deleted — they already live in past appcast items. Entries may already be drafted in the file from when a change landed (breaking changes especially); reuse and polish those drafts rather than rewriting from scratch.

## Format (the subset that survives)

- Sections, in this order, omitting empty ones: `## Breaking changes`, `## Improvements`, `## Fixes`.
- Supported markdown: h2 headings, `- ` bullets, paragraphs, `**bold**`. No nested lists, code fences, links, or version heading (the appcast item adds the title).
- Inline backticks pass through literally in Sparkle — prefer plain text unless quoting an exact identifier.

## Style

English narrative. Complete sentences, present tense, no "we", no promotional tone. Bold lead-in sentence for major items. Use the product names users know: Claude Desktop, Claude Code, Codex, OpenCode, the gateway, the menu. Lead with the behavior and, when it matters, the why (compat, migration, failure mode).

Merge commits that ship one behavior into one bullet: ten sibling `fix(gateway)` TLS commits become one or two items. Never quote commit subjects, file names, scopes, or internal jargon.

## Common Mistakes

| Mistake | Reality |
|---|---|
| Keeping old release sections | The file holds only the new release; older items already live in the appcast |
| One bullet per commit | Notes describe behaviors, not work — merge sibling commits |
| Listing refactors or internal docs | Only observable user impact counts |
| Deriving the range from git tags | No tags exist — range is from the last `chore(release)` commit |
| Avoiding `**bold**` | Bold survives the appcast: `markdownToHtml` converts it to `<strong>` |
