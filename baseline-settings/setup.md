# baseline-settings — setup

**Requires:** Claude Code

## Per-machine values

- `<WSL_USER>` — your WSL username (appears in `statusLine.command` path)

## Files

- `settings.json` → deploys to `~/.claude/settings.json` (merge if file exists; do not overwrite blindly)

## Install

1. If `~/.claude/settings.json` does not exist: copy this module's `settings.json` after substituting `<WSL_USER>` (sed `s|/home/pudge/|/home/<WSL_USER>/|g`).
2. If `~/.claude/settings.json` exists: merge keys. The user's existing entries take precedence on conflicts; ask before overwriting any keys that already have a value.
3. Confirm `python3 -c "import json; json.load(open('~/.claude/settings.json'.replace('~', '$HOME')))"` parses cleanly.

## Verify

- `claude --version` runs without errors.
- Status bar renders (the `statusline-command.sh` deployed by the `statusline` module).
- Permissions allow-list applies (e.g. `git status` doesn't prompt).

## Uninstall

Remove the keys this module added; restore the user's prior `~/.claude/settings.json` from backup if available.
