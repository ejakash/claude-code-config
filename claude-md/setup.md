# claude-md — setup

**Requires:** Claude Code

## Per-machine values

- `<WIN_USER>` — your Windows username; appears in the screenshot folder path inside this `CLAUDE.md`.

## Files

- `CLAUDE.md` → deploys to `~/.claude/CLAUDE.md` (merge if file exists; do not overwrite blindly).

## Install

1. If `~/.claude/CLAUDE.md` does not exist: `sed 's|<WINDOWS_USER>|<YOUR_WIN_USER>|g' CLAUDE.md > ~/.claude/CLAUDE.md`
2. If it exists: merge sections. Sections in this module that are absent from the user's existing file get appended; conflicts get presented to the user.

## Verify

Start a Claude Code session. Confirm the agent honors STT substitutions ("cloud code" → Claude Code), prefers Read/Edit/Grep, and avoids `cd && cmd` compounds.
