# claude-md — setup

**Requires:** Claude Code

## Per-machine values

- `<WINDOWS_USER>` — your Windows username; appears in the screenshot folder path and the DND apps-file path inside this `CLAUDE.md`.

## Conditional sections

Three sections depend on other modules/tools being installed. Drop each one during install if its dependency is absent (each is marked with an HTML comment in the file):

- **.NET Code Quality** — requires the `rules/` module (`~/.claude/rules/dotnet.md`).
- **View markdown deliverables in the themed viewer** — requires the wezterm-webview viewer.
- **Claude Code notification "do not disturb"** — requires claude-waiting-notification and `~/.claude/scripts/claude-dnd.sh`.

## Files

- `CLAUDE.md` → deploys to `~/.claude/CLAUDE.md` (merge if file exists; do not overwrite blindly).

## Install

1. If `~/.claude/CLAUDE.md` does not exist: `sed 's|<WINDOWS_USER>|<your Windows username>|g' CLAUDE.md > ~/.claude/CLAUDE.md`, then delete any conditional sections whose dependency isn't installed.
2. If it exists: merge sections. Sections in this module that are absent from the user's existing file get appended; conflicts get presented to the user.

## Verify

Start a Claude Code session. Confirm the agent honors STT substitutions ("cloud code" → Claude Code), prefers Read/Edit/Grep, avoids `cd && cmd` compounds, and omits AI-attribution footers from commits.
